use strict;
package AppCore::Web::SimpleListView;
{
	#use base qw/AppCore::Web::BasicView/;
	use AppCore::Web::Common;
	use JSON qw/to_json/;
	
	
	####################################
	
	sub _new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};
		
		$args->{file} ||= '';
		
		$args->{tmpl} = AppCore::Web::Common::load_template($args->{file});
		$args->{req}  = $req;
		
		die "Unable to load template '$args->{file}'" if !$args->{tmpl} && $args->{file};
		
		my $self = bless $args, $class;
		
		#print STDERR Dumper($req->page_path);
		
		if($self->tmpl)
		{
			$self->tmpl->param(page_path => $req->page_path);
			$self->tmpl->param(app_root  => $req->app_root);
		}
		
		return $self;
	}
	
	sub set_template
	{
		my $self = shift;
		my $file = shift;
		$self->{file} = $file;
		# TODO: This is a hack - we just assume that if $file is a reference, it's HTML::Template-compatible,
		# but I'm too lazy to do UNIVERSAL::isa for the different compatible derivations right now...
		return $self->{tmpl} = ref $file ?  $file : AppCore::Web::Common::load_template($file);
	}
	
	sub set_file{shift->set_template(@_)}
	
	
	sub x
	{
		my($x,$k,$v)=@_;
		if(defined $v)
		{
			$x->{$k}=$v;
	#         	print STDERR AppCore::Common::MY_LINE().": x('$k') := '$v'\n";
		}
	
		$x->{$k};
	}
	
	sub req { shift->{req} }
	
	sub tmpl { shift->{tmpl} }
	
	#sub output { shift->tmpl->output }
	
	
	# Provide basic accessor to a 'model' attribute 
	sub model { shift->{model} }
	sub set_model
	{
		my $self = shift;
		my $model = shift;
		$self->{model} = $model;
	}
	
	
	
	sub convert_model_to_hash
	{
		my $self = shift;
		my $model = shift || $self->model;
		
		my %hash;
		
		foreach my $col ($model->columns)
		{
			my $fm = $model->field_meta($col);
			my $val = $model->get($col);
			
			if($fm && $fm->{linked})
			{
				$hash{$col.'_raw'} = $val;
				
				eval 'use '.$fm->{linked};
				my $x = eval {$fm->{linked}->stringify($val)};
				$val = $x if !$@;
			}
			$hash{$col} = $val;
		}
		
		return \%hash;
	
	}
	####################################
	
	sub new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};
		
		$args->{file} ||= ''; #givemea404.tmpl';
		$args->{output_format} ||= 'html';
		
		#return $class->SUPER::new($req,$args);
		return $class->_new($req,$args);
	}
	
	sub set_output_format
	{
		my $self = shift;
		my $fmt = lc shift || 'html';
		if($fmt ne 'html' && 
		   $fmt ne 'xls'  &&
		   $fmt ne 'json')
		{
			warn $@ = ref($self)."->set_output_fmt('$fmt'): Invalid/unknown output format '$fmt', defaulting to HTML.";
			return undef;
		}
		return $self->{output_format} = $fmt;
	}
	
	sub output_format
	{
		return lc shift->{output_format};
	}
	
	sub set_paging
	{
		my $self = shift;
		my ($start,$length) = @_;
		$self->{page_start} = $start ? $start : 0;
		$self->{page_length} = $length ? $length : 50;
	}
	
	sub set_message
	{
		my $self = shift;
		my $msg = shift;
		$self->{msg} = $msg;
	}
	
	sub page_start  {shift->{page_start}}
	sub page_length {shift->{page_length}}
	
	sub set_filter_name 
	{
		my $self = shift;
		$self->{filter_name} = shift;
	}
	
	sub filter_name { shift->{filter_name} }
	
	# Method: enable_advanced_filters($table_list,$filter_cookie='advanced_filters_query_packet',$bookmark_controller_url='advfilter_bookmarks'
	# Turns on advanced filter output in the list view. (Must also be enabled on the model.)
	# It will load the bookmarked filters from the model via $model->get_advanced_filters_bookmarks().
	# If $bookmark_controller_url is not absolute (starts with http:// or /), it will prepend $req->page_path to the value in 
	# $bookmark_controller_url and pass it to the template as the controller URL for saving bookmarks to via ajax/json
	sub enable_advanced_filters
	{
		my $self = shift;
		#die Dumper  $self->model->cdbi_class->meta->{table_list};
		my $table_list = shift || ($self->model ? $self->model->cdbi_class->meta->{table_list} : []);
		my $filter_cookie = shift || 'advanced_filters_query_packet';
		my $bookmark_controller_url = shift || 'advfilter_bookmarks';
		$self->{advanced_filter_cookie_name} = $filter_cookie;
		$self->{advanced_filter_table_list} = $table_list;
		$self->{advanced_filter_bookmark_controller_url} = $bookmark_controller_url;
		$self->{advanced_filter_enabled} = 1;
	}
	
	sub get_advanced_filter_cookie_name
	{
		shift->{advanced_filter_cookie_name};
	}
		
	
	sub create_filter_list
	{
		my $class = shift;
		my $model = shift;
		my $filter_ref  = shift;
	
		#print STDERR "cur_filter='$cur_filter'\n";
		my @filters = $model->get_complex_filters;
		
		my @filter_list = 
			map  {{
				key	 => $_->{id},
				name	 => $_->{name},
				hr	 => $_->{id} eq '-',
				selected => $filter_ref->{id} eq $_->{id}
			}} # Build hashref from list
			grep { AppCore::Common->context->current_user->check_acl($_->{acl} || ['EVERYONE'],1) } # Filter out any filters that are restricted
			@filters; # Grab list of keys
		$filter_list[$#filter_list]->{last} = 1 if @filter_list;
		
		return @filter_list;
		
	}
	
	sub set_query_tokenizer_hook
	{
		my ($self, $hook) = @_;
		
		$self->{_query_tokenizer_hook} = $hook;
	}
	
	sub prep_tokenized_query
	{
		my $self  = shift;
		my $model = $self->model;
		my $query = shift || $model->filter;
		my @term_words = AppCore::DBI::SimpleListModel::parse_ssv($query);
		
		my @tokenized_list = map {
			{
				text => $_,
				selected => 1
			}
		} @term_words;
		
		my $hook = $self->{_query_tokenizer_hook};
		
		if(ref $hook eq 'CODE')
		{
			return $hook->($self, \@tokenized_list, \@term_words);
		}
		
		return \@tokenized_list;
	}
	
	
	# This are only defined AFTER calling output()
	sub output_list { shift->{output_list} }
	sub output_length { shift->{output_length} }
	
	sub output
	{
		my $self = shift;
		my $output_args = shift|| {};
		
		my $fmt   = $self->output_format;
		my $model = $self->model;
		my $req   = $self->req;
		
		if($fmt eq 'xls')
		{
			use Spreadsheet::WriteExcel;
			use File::Slurp;
			
			my $tmp_file = "/tmp/listview$$.xls";
			my $workbook = Spreadsheet::WriteExcel->new($tmp_file);
			
			my $class = $model->cdbi_class;
			
			$output_args->{columns} ||= ($self->{advanced_filter_enabled} ? $self->{advanced_filter_table_list} : undef) || $class->meta->{table_list} || [];
			
			# Add a worksheet
			my $worksheet = $workbook->add_worksheet($output_args->{sheet_name} || 'Sheet 1');
			
			#  Add and define a format
			my $hdr1 = $workbook->add_format(); # Add a format
			$hdr1->set_bold();
			$hdr1->set_color('black');
			#$hdr1->set_border(2);
			$hdr1->set_bottom();
			$hdr1->set_align('center');
			
			my $hdr2 = $workbook->add_format(); # Add a format
			$hdr2->set_bold();
			$hdr2->set_color('black');
			#$hdr2->set_border(2);
			$hdr2->set_bottom();
			
			my $fmt_bold = $workbook->add_format(); # Add a format
			$fmt_bold->set_bold();
			$fmt_bold->set_color('black');
			
			my $f_a_r = $workbook->add_format(); # Add a format
			$f_a_r->set_align('right');
			
			my $f_b = $workbook->add_format(); # Add a format
			$f_b->set_bold();
			
			my $y=0;
			my $x=0;
			
			
		
			my $filter = $model->complex_filter();
			
			#my @filter_list = $self->create_filter_list($model,$filter);
			#$tmpl->param(filter_list=>\@filter_list);
			#$tmpl->param(filter_name=>$filter->{name}) if $filter;
			
		
# 			
# 			## ?? why rename?? wierdo...was because i was trying to figure out if i should add an '?' or a  '&'...whatever
# 			my $page = $path;
# 			$page =~ s/\/$//g;
# 			
# 			## Setup the header
# 			my @columns = map
# 				{
# 					$_->{field_name} = $_->{field};
# 					$_->{title}      = $_->{title} ? $_->{title} : AppCore::Common::guess_title($_->{field});
# 					$_->{current_sort_column} = 1 if $model->sort_column eq $_->{field};
# 					$_->{'sort_dir_' . $model->sort_direction eq 'ASC' ? 'asc' : 'desc'} = 1;
# 					$_->{page}  = $page;
# 					
# 					# If we were using an advanced filtering model (filters per col)
# 					#$_->{has_filter} = 1 if $model->filter->is_filtered($_->filed_name}; 
# 					
# 					$_;
# 				} 
# 				$model->columns;
# 			
# 			$tmpl->param(header => \@columns); 
			
			$worksheet->write($y,$x++,$output_args->{page_title} || 'Database Export ('.(ref($class) ? ref($class) : $class).')',$fmt_bold); # if $output_args->{page_title};
			$x=0; 
			$y++;
			$worksheet->write($y,$x++,'Date: ');
			$worksheet->write($y,$x++,AppCore::Common::date(),$fmt_bold);
			$worksheet->insert_image(0,4, $output_args->{logo_image_file})
				if $output_args->{logo_image_file};
			
			## Compile and add the list values to the template
			my $rows = $model->compile_list();
			
			## Let the template know if we were searched and how 
			#$tmpl->param(query => $model->filter);
			#$tmpl->param(is_filtered => $model->is_filtered);
			
			# do filter row highlighting here
			#my $filter_value_regex = _regexp_escape($model->filter);
			
			#my $row_highlighting_enabled = defined $self->{enable_row_highlighting} ? $self->{enable_row_highlighting} : 1;
			
			$y++;
			$y++;
			
			my @cols = @{ $output_args->{columns} || [] };
			
			#print STDERR Dumper \@cols;
			my %fm_cache;
			# Write a formatted and unformatted string, row and column notation.
			$x=0;
			foreach my $col (@cols)
			{
			#	next if !defined $_->{col};
				#print STDERR "$y,$x: $_->{name}\n";
				my $fm = $class->field_meta($col);
				$fm_cache{$col} = $fm;
				next if !$fm;
				$worksheet->write($y, $x++, $fm->{title} || AppCore::Common::guess_title($fm->{field}), ($fm->{td_align} eq 'center')?$hdr1:$hdr2); 
			}
				
			$y++;
			$worksheet->freeze_panes($y, 0); # 1 row
			
			
			my $fmter = $output_args->{column_formatter};
			
			my $count = 0;
			foreach my $row (@$rows)
			{
				$self->row_mudge_hook($row);
				
				$x=0;
				foreach my $col (@cols)
				{
					my $fm = $fm_cache{$col};
					next if !$fm;
					$worksheet->write($y,$x++,$fmter ? $fmter->($self,$row->{$col},$_,$row) : "".$row->{lc($col)});
				}
				$y++; 
			}
			
			$self->{output_list}   = $rows;
			$self->{output_length} = $rows && ref $rows ? $#{$rows} +1 : 0;
				
			
			#$tmpl->param(list => $rows);
			#$tmpl->param(list_length => $rows && ref $rows ? $#{$rows} +1 : 0);
			
			## Misc closing variables
			#$tmpl->param(filter_string => $model->filter_text);
			
# 			$tmpl->param(view_message => $self->{msg});
# 			
# 			$tmpl->param(prev_page_path => $self->req->prev_page_path);
# 			
# 			if($self->{advanced_filter_enabled})
# 			{
# 				# Add the advanced filter schema data
# 				$tmpl->param(advanced_filter_cookie_name => $self->{advanced_filter_cookie_name});
# 				
# 				my $url = $self->{advanced_filter_bookmark_controller_url};
# 				if($url !~ /^(http:|\/)/i)
# 				{
# 					$url = $self->req->page_path . '/'. $url;
# 				}
# 				$tmpl->param(advanced_filter_bookmark_controller_url => $url);
# 				
# 				my $class = $self->model->cdbi_class;
# 				my @schema;
# 				foreach my $col (@{ $self->{advanced_filter_table_list} || [] })
# 				{
# 					my $fm = $class->field_meta($col);
# 					if(!$fm)
# 					{
# 						#warn "$self\:\:output(): Invalid table list column name '$col'";
# 						push @schema, {};
# 					}
# 					else
# 					{
# 						push @schema, 
# 						{
# 							title	=> $fm->{title} || AppCore::Common::guess_title($fm->{field}),
# 							column	=> $fm->{field},
# 							type	=> $fm->{type},
# 							linked	=> $fm->{linked},
# 							filtersAvail => $self->model->compile_available_filter_values($fm->{field}),
# 						};
# 					}
# 				}
# 				
# 				#die Dumper \@schema, $self->{advanced_filter_table_list};
# 				$tmpl->param(advanced_filters_schema => to_json(\@schema));
# 				
# 				#print STDERR AppCore::Common::print_stack_trace();
# 				my @bookmarks = $model->get_advanced_filters_bookmarks();
# 				if(@bookmarks)
# 				{
# 					my @sys_list;
# 					my @user_list;
# 					@bookmarks = sort {$a->name cmp $b->name} @bookmarks;
# 					foreach my $bm (@bookmarks)
# 					{
# 						next if !$bm;
# 						my $hash;
# 						$hash->{$_} = ''.$bm->get($_) foreach $bm->columns;
# 						$hash->{user_name} = $bm->userid->display() if $bm->userid && $bm->userid->id;
# 						if($bm->is_system)
# 						{
# 							push @sys_list, $hash;
# 						}
# 						else
# 						{
# 							push @user_list, $hash;
# 						}
# 					}
# 					
# 					my @bm_list;
# 					push @bm_list, @sys_list;
# 					push @bm_list, {divider=>1} if @sys_list && @user_list;
# 					push @bm_list, @user_list;
# 					
# 					$tmpl->param(advanced_filters_bookmarks => to_json(\@bm_list));
# 				}
# 				
# 			}

			$workbook->close;
			#(
			
			my $tmp =  read_file( $tmp_file, binmode => ':raw' );
	 		unlink($tmp_file);
			
	 		return $tmp;
			
			
			#return AppCore::Form->post_process($self->SUPER::output());
		}
		else
		{

			# Will be either returned to be converted to JSON or applied to the template, depending on output_format
			my $output_data = {}; 
			
			my $path  = $req->page_path;
			
			my $view_page_path_prefix = $path; #$req->app_root . '/salesorders';
			
			my $filter = $model->complex_filter();
			
			my @filter_list = $self->create_filter_list($model,$filter);
			$output_data->{filter_list} = \@filter_list;
			$output_data->{filter_name} = $filter->{name} if $filter;
			
		
			
			## ?? why rename?? wierdo...was because i was trying to figure out if i should add an '?' or a  '&'...whatever
			my $page = $path;
			$page =~ s/\/$//g;
			
			## Setup the header
			my @columns = map
				{
					$_->{field_name} = $_->{field};
					$_->{title}      = $_->{title} ? $_->{title} : AppCore::Common::guess_title($_->{field});
					$_->{current_sort_column} = 1 if $model->sort_column eq $_->{field};
					$_->{'sort_dir_' . $model->sort_direction eq 'ASC' ? 'asc' : 'desc'} = 1;
					$_->{page}  = $page;
					
					# If we were using an advanced filtering model (filters per col)
					#$_->{has_filter} = 1 if $model->filter->is_filtered($_->filed_name}; 
					
					$_;
				} 
				$model->columns;
			
			$output_data->{header} = \@columns;
			
			
			## Basic paging support implementation
			my $total_rows = $model->get_total_rows();
			$output_data->{total_rows} = $total_rows;
	# 		
	# 		use Data::Dumper;
	# 		print STDERR Dumper([$self->page_start,$self->page_length]);
			
			my $end_of_page = $self->page_start + $self->page_length;
			
			my $paged_flag = 0;
			if($end_of_page < $total_rows)
			{
				$paged_flag = 1;
				$output_data->{next_url} = $page . '?start='.$end_of_page.'&length='.$self->page_length;
			}
			
			if($self->page_start > 0 )
			{
				$paged_flag = 1;
				
				my $new_start = $self->page_start - $self->page_length;
				$output_data->{prev_url} = $page . '?start='.( $new_start < 0 ?  0 : $new_start ).'&length='.$self->page_length;
			}
			
			$output_data->{fake_page_start}  = $self->page_start + 1;
			$output_data->{page_start}  = $self->page_start;
			$output_data->{page_length} = $self->page_length;
			$output_data->{page_end}    = $end_of_page;
			$output_data->{paged_flag}  = $paged_flag;
			
			#print STDERR "pagelen = ".$self->page_length."\n";
			
			my $new_end = $self->page_start + $self->page_length ;	
			my $actual_page_length = ( $new_end > $total_rows ? $total_rows - $self->page_start : $self->page_length );
			$output_data->{actual_page_end} = $self->page_start + $actual_page_length;
				
			## Compile and add the list values to the template
			my $rows = $model->compile_list($self->page_start, $self->page_length);
			#die Dumper $rows;
			
			## Let the template know if we were searched and how 

			$output_data->{query}           = $model->filter;
			$output_data->{query}           =~ s/\%/ /g;
			$output_data->{is_filtered}     = $model->is_filtered;
			$output_data->{query_tokenized} = $self->prep_tokenized_query();
			
			# do filter row highlighting here
			my $filter = $model->filter;
			my $filter_value_regex = _regexp_escape($filter);
			
			my $row_highlighting_enabled = defined $self->{enable_row_highlighting} ? $self->{enable_row_highlighting} : 1;
			
			my $count = 0;
			foreach my $row (@$rows)
			{
				foreach my $key (keys %$row)
				{
					$row->{$key} = '&nbsp;' if $row->{$key} eq '' || !defined $row->{$key};
					
					if($filter_value_regex && $row_highlighting_enabled) 
					{
						$row->{$key.'_orig'} = $row->{$key};
						$row->{$key} =~ s/($filter_value_regex)/<b class='filter_highlight'>$1<\/b>/gi;
					}
				}
				
				$row->{odd_flag}  = ++ $count % 2 == 0;
				$row->{page}      = $view_page_path_prefix;
				$row->{_filter}   = $filter;
				
				$self->row_mudge_hook($row);
			}
			
			$self->{output_list} = $rows;
			$self->{output_length} = $rows && ref $rows ? $#{$rows} +1 : 0;
			
			$output_data->{list}        = $rows;
			$output_data->{list_length} = $self->{output_length};
			
			# Also fill in a custom parameter name if given in the output args
			# User could also decide to just set a param_prefix, below.
			$output_data->{$output_args->{list_param_name}} = $rows
				if $output_args->{list_param_name};
			
			## Misc closing variables
			
			$output_data->{view_message}   = $self->{msg};
			
			$output_data->{prev_page_path} = $self->req->prev_page_path;
			
			if($self->{advanced_filter_enabled})
			{
				# Add the advanced filter schema data
				$output_data->{advanced_filter_cookie_name} = $self->{advanced_filter_cookie_name};
				
				my $url = $self->{advanced_filter_bookmark_controller_url};
				if($url !~ /^(http:|\/)/i)
				{
					$url = $self->req->page_path . '/'. $url;
				}
				$output_data->{advanced_filter_bookmark_controller_url} = $url;
				
				my $class = $self->model->cdbi_class;
				my @schema;
				foreach my $col (@{ $self->{advanced_filter_table_list} || [] })
				{
					my $fm = $class->field_meta($col);
					if(!$fm)
					{
						#warn "$self\:\:output(): Invalid table list column name '$col'";
						push @schema, {};
					}
					else
					{
						push @schema, 
						{
							title	=> $fm->{title} || AppCore::Common::guess_title($fm->{field}),
							column	=> $fm->{field},
							type	=> $fm->{type},
							linked	=> $fm->{linked},
							filtersAvail => $self->model->compile_available_filter_values($fm->{field}),
						};
					}
				}
				
				#die Dumper \@schema, $self->{advanced_filter_table_list};
				$output_data->{advanced_filters_schema} = to_json(\@schema);
				
				#print STDERR AppCore::Common::print_stack_trace();
				my @bookmarks = $model->get_advanced_filters_bookmarks();
				if(@bookmarks)
				{
					my @sys_list;
					my @user_list;
					@bookmarks = sort {$a->name cmp $b->name} @bookmarks;
					foreach my $bm (@bookmarks)
					{
						next if !$bm;
						my $hash;
						$hash->{$_} = ''.$bm->get($_) foreach $bm->columns;
						$hash->{user_name} = $bm->userid->display() if $bm->userid && $bm->userid->id;
						if($bm->is_system)
						{
							push @sys_list, $hash;
						}
						else
						{
							push @user_list, $hash;
						}
					}
					
					my @bm_list;
					push @bm_list, @sys_list;
					push @bm_list, {divider=>1} if @sys_list && @user_list;
					push @bm_list, @user_list;
					
					$output_data->{advanced_filters_bookmarks} = to_json(\@bm_list);
				}
				
			}
			
			if($fmt eq 'json')
			{
				return $output_data;
			}
			
			my $param_prefix = $output_args->{param_prefix} || '';
			
			my $tmpl = $self->tmpl;
			foreach my $key (keys %$output_data)
			{
				$tmpl->param(
					($param_prefix ? $param_prefix.'_' : '') . $key => $output_data->{$key}
				);
			}
			
			#return AppCore::Form->post_process($self->SUPER::output());
			#return AppCore::Form->post_process($self->output());
			return $tmpl->output();
		}
	}
	
	sub content_type
	{
		my $self = shift;
		my $fmt = $self->output_format;
		return $fmt eq 'xls'  ? 'application/vnd.ms-excel' : 
		       $fmt eq 'json' ? 'application/json' :
		                        'text/html';
	}
	
	sub row_mudge_hook
	{
		my $self = shift;
		my $row = shift;
		
		if(ref $row eq 'CODE')
		{
			$self->{_row_mudge_hook} = $row;
			return;
		}
		
		return if !$self->{_row_mudge_hook};
		
		if($row && ref $self->{_row_mudge_hook} eq 'CODE')
		{
			$self->{_row_mudge_hook}->($row);
		}
	}
	
	##############################################################################
	# Group: Private Methods
	
	# Function: _regexp_escape
	# Escapes characters special to regex's in $val. Also trims spaces from start and end of string. 
	sub _regexp_escape#($val)
	{
		my $regex = shift;
		$regex =~ s/(^\s+|\s+$)//g;
		
		# Apply same wildcard formatting to highlight regex
		$regex =~ s/\s+/ /g;		# collapse spaces
		$regex =~ s/[^\da-z]/ /g;	# remove anything not a digit or a letter
		
		# Escape any odd characters
		$regex =~ s/([^\w\s\d])/\\$1/g;
		
		$regex =~ s/(.)/$1./g;		# insert '.' between every character
		$regex =~ s/\.\s*\././g;	# collapse '% %' into '%'
		$regex =~ s/\.$//g;		# remove '.' from end
		$regex =~ s/\./.*/g;		# make '.' expansive
		
		#die $regex;
		
		
		return $regex;
	}
		

};


1;

