#
# Module: AppCore::Web::ReportViewer;
#
# ReportViewer is a generic untility class that lets you throw a blob of SQL at it and it makes a nice pretty report out of it, complete
# with a parameter UI thanks to AppCore::Web::Form.
#
# The actual specs of the report model is a only a wee bit more complex than that - but really it is that simple - throw SQL together,
# throw it into a hash with some other nice fields, and voila - the ReportViewer (and whatever template you use)
# does the dirty work of running the query, throwing it in the template, adding the "options" UI, creating the table header and body, etc.
# Sort of like how the "wizard" side of Microsoft Reporting Services works - quick and easy reporting, or that's the idea anyway.
#
# See the __DATA__ section for a complete working example report model (well, working if you have those tables and classes)
# and a generic report viewer template you can use for just about any basic report and works with this class.
#
package AppCore::Web::ReportViewer;
{
	use strict;

	use AppCore::Web::Common;
	use AppCore::Web::Form;

	use JSON qw/encode_json/;

	####################################

	our $STASH;

	sub set_stash
	{
		shift;
		$STASH = shift;
	}

	sub stash { $STASH }

	sub _new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};

		$args->{file} ||= '';

		$args->{tmpl} = AppCore::Web::Common::load_template($args->{file}) if $args->{file};
		$args->{req}  = $req;

		die "Unable to load template '$args->{file}'" if !$args->{tmpl} && $args->{file};

		my $self = bless $args, $class;

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

	sub set_file{ shift->set_template(@_) }


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

	sub session_id { shift->{session_id} }

	# The session_id param, if provided,
	# is used to replace the string "__tmp_SESSIONID_"
	# in SQL with "__tmp_${session_id}"
	# NOTE: Replace is case sensitive, just to be safe
	sub set_session_id {
		my $self = shift;
		$self->{session_id} = shift;
	}

	####################################

	sub new
	{
		my $class = shift;
		my $req   = shift;
		my $args  = shift || {};

		$args->{file} ||= '';
		$args->{output_format} ||= 'html';

		return $class->_new($req, $args);
	}

	sub set_report_model
	{
		my ($self, $report) = @_;
		$self->{report_model} = $report;

		$self->audit_report_model();
	}

	sub report_model { shift->{report_model} };

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
		$self->{page_start}  = $start ? $start : 0;
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

	sub audit_report_model
	{
		my $self = shift;
		my $report = $self->report_model;

		#die Dumper $report->{args};

		my $field_counter = 0;
		foreach my $arg (
			grep { !$_->{hidden} }
				@{ $report->{args} || [] })
		{
			# Perform an in-place audit of existing values
			$arg->{field} = 'field'.(++$field_counter)
				if !$arg->{field};

			$arg->{type} = 'database'
				if $arg->{linked} &&
				  !$arg->{type};

# 			$arg->{placeholder} = $arg->{label}
# 				if !$arg->{placeholder};
		}
	}

	sub generate_report
	{
		my ($self, $arg_hash, $ignore_incomplete, $pagination_url_base, $disable_render) = @_;

		# NOTE: If $pagination_url_base is defined,
		# generate_report() will ATTEMPT to paginate
		# SQL-provided data. Note that the report
		# MUST define 'count_sql' in addition to
		# the 'sql' key in order for generate_report()
		# to be able to paginate the data.

		my $report = $self->report_model;

		# Store arg hash for use in hooks so it's indexed by field (just because we're lazy)
		$report->{arg_hash} = $arg_hash;

		my $output_data = {};

		# Get the args
		my $arg_data_complete = 1;
		my @arg_data;
		{
			my $arg_meta = $report->{args};

			foreach my $arg_ref (@{$arg_meta || []})
			{
				# Get arg value from UI
				if(defined $arg_hash)
				{
					$arg_ref->{value}
						= $arg_hash->{$arg_ref->{field}}
						if !$arg_ref->{hidden};

					$arg_hash->{$arg_ref->{field}} =
					$arg_ref->{value} = undef
						if $arg_ref->{type} eq 'date' &&
						  !$arg_ref->{value};
				}

				if(!defined $arg_ref->{value} &&
				   !$arg_ref->{allow_null})
				{
					$arg_data_complete = 0;
				}

				push @arg_data, $arg_ref;
			}

			#die Dumper \@arg_data, $arg_meta, $arg_hash;
		}

		$arg_data_complete = 1
			if $ignore_incomplete;

		$output_data->{arg_data_complete} = $arg_data_complete;

		#die Dumper $output_data, $report, \@arg_data;

		# Flag for use in the template
		my @visible_args = grep { !$_->{hidden} } @{ $report->{args} || [] };
		$output_data->{has_visible_args} = scalar(@visible_args) > 0;

		#die Dumper \@arg_data, $arg_hash, $arg_data_complete;

		# Apply report mudge hook if present
		# Since the list hook gets the report, it can change columns (or anything else) as desired
		if(ref $report->{report_mudge_hook} eq 'CODE')
		{
			$report->{report_mudge_hook}->($report, $arg_data_complete, $arg_hash);
		}


		# Get columns if given in $report
		my @report_columns;
		if(ref $report->{columns} eq 'ARRAY')
		{
			@report_columns = @{$report->{columns} || []};

			# Audit columns to make sure they are hashrefs
			my @tmp_list;
			foreach my $col (@report_columns)
			{
				if(ref $col ne 'HASH')
				{
					push @tmp_list, { field => $col };
				}
				else
				{
					push @tmp_list, $col;
				}
			}

			@report_columns = @tmp_list;
		}

		$arg_data_complete = 0 if $disable_render;

		# Get the data
		my @report_data;
		if($arg_data_complete)
		{
			if($report->{sql})
			{
				my @sql_args = map {
					ref $_->{value} eq 'CODE'
						? $_->{value}->($report, $self->stash)
						: $_->{value} }
					grep { !$_->{exclude_from_sql} }
					@arg_data;

				# Make a copy of the SQL string because if pagination is enabled,
				# we'll add a 'LIMIT' to it, and we don't want that LIMIT
				# inadvertantly persisting, e.g. in ModPerl/FastCGI enviros
				my $report_sql = $report->{sql};

				# Replace special table prefix "__tmp_SESSIONID_" with "__tmp_${sessoinid}"
				# so that each run of this report can use unique tmp tables
				if($self->session_id) {
					my $sanatized_session_id = $self->session_id;
					$sanatized_session_id =~ s/[^a-zA-Z0-9]//g;
					$report_sql =~ s/__tmp_SESSIONID_/__tmp_${sanatized_session_id}_/g;
				}

				#die Dumper \@sql_args;
				if($pagination_url_base &&
				   $self->output_format ne 'xls')
				{
					if($report->{count_sql})
					{
						# Count rows
						my ($listref, $last_sth) =
							AppCore::DBI->bulk_execute(
								$report->{count_sql},
								@sql_args
							);

						my @count_data = @{ $listref || [] };
						my $row_hash   = (shift @count_data);
						my $total_rows = (values %{$row_hash || {}})[0];

						# Templates should check for this value to be defined before displaying pagination controls
						$output_data->{total_rows} = $total_rows;

						# Build paging data
						my $end_of_page = $self->page_start + $self->page_length;

						$pagination_url_base .= $pagination_url_base =~ /\?/ ? '&' : '?';

						my $paged_flag = 0;
						if($end_of_page < $total_rows)
						{
							$paged_flag = 1;
							$output_data->{next_url} = $pagination_url_base . 'start='.$end_of_page.'&length='.$self->page_length;
						}

						if($self->page_start > 0 )
						{
							$paged_flag = 1;

							my $new_start = $self->page_start - $self->page_length;
							$output_data->{prev_url} = $pagination_url_base . 'start='.( $new_start < 0 ?  0 : $new_start ).'&length='.$self->page_length;
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


						# Slightly hackish: Modify the report SQL:
						my ($start, $len) = ($self->page_start, $self->page_length);
						{
							$start = int($start)+0;
							$len   = int($len)+0;
							$report_sql =~ s/;?(\s|\n)*$/ limit $start, $len/;

							#print STDERR "[Debug] New report_sql after pagination: [[$report_sql]]\n";
						}
					}
					else
					{
						undef $pagination_url_base;
						warn "ReportViewer: Unable to paginate data: 'count_sql' was not provided";
					}
				}

				my ($listref, $last_sth) =
					AppCore::DBI->bulk_execute(
						$report_sql,
						@sql_args
					);

				@report_data = @{ $listref || [] };

				# Extract order and name of fields returned if not specified
				# in the report config
				if(!@report_columns &&
					$last_sth)
				{
					my @field_list;

					# Following is based on http://search.cpan.org/~capttofu/DBD-mysql-4.028/lib/DBD/mysql.pm#STATEMENT_HANDLES
					my $names = $last_sth->{'NAME'};
					my $numFields = $last_sth->{'NUM_OF_FIELDS'} - 1;
					for my $i (0 .. $numFields) {
						#printf("%s%s", $i ? "," : "", $$names[$i]);
						push @field_list, $$names[$i];
					}

					@report_columns = map {{
						field => $_,
						title => guess_title($_)
					}} @field_list;
				}

			}
			elsif(ref $report->{data} eq 'ARRAY')
			{
				@report_data = @{ $report->{data} || [] };

				if(!@report_columns)
				{
					my $columns_listref = undef;

					# Since this is raw arrayref data, we must grab the list
					# of columns from the first row of data if not specified
					# in report configuration.
					if(@report_data)
					{
						my $first_row = $report_data[0];
						if(ref $first_row eq 'HASH')
						{
							# Sort keys of first row alphabetically
							my @keys = keys %{$first_row || {}};
							@keys = sort { $a cmp $b } @keys;

							$columns_listref = @keys;
						}
					}

					# Now $columns_listref SHOULD hold some data -
					# If its just a simple ARRAY of scalars, then convert
					# it to an array of hashrefs of {field,title} keys at minimum.
					# However, if the first row of $columns_listref is a HASH,
					# we graciously assume the data is in the right format and
					# just pass it on.
					if(ref $columns_listref eq 'ARRAY')
					{
						@report_columns = map {{
							field => $_,
							title => guess_title($_)
						}} $columns_listref;
					}
				}
			}
			elsif(ref $report->{data} eq 'CODE')
			{
				# Execute the code in {data}
				my ($data_listref,
					$columns_listref) =
					$report->{data}->(
						$report,
						\@arg_data,
						$self->stash
					);

				@report_data = @{ $data_listref || [] };

				if(!@report_columns)
				{
					# If the {data} coderef did NOT return a $columns_listref,
					# then we just use the keys of the first row of data
					if(!$columns_listref &&
						ref $data_listref eq 'ARRAY')
					{
						my $first_row = $data_listref->[0];
						if(ref $first_row eq 'HASH')
						{
							# Sort keys of first row alphabetically
							my @keys = keys %{$first_row || {}};
							@keys = sort { $a cmp $b } @keys;

							$columns_listref = @keys;
						}
					}

					# Only if @report_columns is not filled by the report config ...
					# Now $columns_listref SHOULD hold some data -
					# If its just a simple ARRAY of scalars, then convert
					# it to an array of hashrefs of {field,title} keys at minimum.
					# However, if the first row of $columns_listref is a HASH,
					# we graciously assume the data is in the right format and
					# just pass it on.
					if(ref $columns_listref eq 'ARRAY')
					{
						my $first_row = $columns_listref->[0];
						if(ref $first_row ne 'HASH')
						{
							@report_columns = map {{
								field => $_,
								title => guess_title($_)
							}} $columns_listref;
						}
						else
						{
							@report_columns = @{ $columns_listref };
						}
					}
				}
			}
			else
			{
				die "No data and no SQL in report";
			}

			# Apply list mudge hook if present
			# Since the list hook gets the entire data set, it can combine/remove rows as desired
			if(ref $report->{list_mudge_hook} eq 'CODE')
			{
				@report_data = @{ $report->{list_mudge_hook}->(\@report_data, $report) };
			}

			# Apply row mudge hook if present
			# Run row mudge after list mudge because list_mudge_hook could potentially change the number of rows
			if(ref $report->{row_mudge_hook} eq 'CODE')
			{
				foreach my $row (@report_data)
				{
					$report->{row_mudge_hook}->($row, $report);
				}
			}

			# Audit data in report columns
			foreach my $data (@report_columns)
			{
				next if ref $data ne 'HASH';
				$data->{title} = guess_title($data->{field})
					if !$data->{title};
			}

			# Convert the report data into an arrayref of hashrefs containing an arrayref of columns containing a hashref with a value arg
			# E.g. convert [{ fooobar=>framitz }] to [{report_columns=>[{field=>foobar,value=>framitz}, ...]}]
			# where the '...' in the previous example contains foobar=>framitz and any other original keys from the original data
			foreach my $row (@report_data)
			{
				my @columns = map {{
					field => $_->{field},
					title => $_->{title},
					value => exists $row->{$_->{field}} ?
						$row->{$_->{field}}    :
						$row->{lc($_->{field})},
				}} @report_columns;

				$row->{report_columns} = \@columns;
			}

			$output_data->{columns} = \@report_columns;
			$output_data->{data}    = \@report_data;
			$output_data->{data_count} = scalar(@report_data);

			# Apply output hook if present
			if(ref $report->{output_hook} eq 'CODE')
			{
				$report->{output_hook}->($output_data, $report);
			}
		}

		return $output_data;
	}

	sub output
	{
		my $self = shift;

		my $disable_render = $self->{disable_render};

		my $req = $self->req;

		my $report = $self->report_model;

		# Create a hash for use in getting args from the UI
		my %arg_hash = map {

			# The resultant hash is just field=>value
			$_->{field} => $_->{value};

		} grep { !$_->{hidden} }
			@{ $report->{args} || [] };

		# Hash for rebuilding the query to recreate this report
		my %query_args;

		# Load any values incomming from user into the arg hash
		if($req->{'AppCore::Web::Form::ModelMeta.uuid'})
		{
			AppCore::Web::Form->store_values($req, {
				args	=> \%arg_hash,
			});

			$query_args{'AppCore::Web::Form::ModelMeta.uuid'} = $req->{'AppCore::Web::Form::ModelMeta.uuid'};
			$query_args{'#args.'.$_} = $req->{'#args.'.$_}
				foreach keys %arg_hash;
		}
		else
		{
			# This block allows us to programatically generate URLs that pre-populate arguments to the report (and thus, run the report)
			# without having to know the ModelMeta.uuid - which may not exist before calling this report.
			# This block, therefore, allows us to generate URLs in code like:
			#     /office/reports/patient-bydoc?args.doctorid=52
			# (Note we make the '#' optional in args because it's cleaner and looks better - yes, that's really the only reason I made it optional.)

			foreach my $key (keys %$req)
			{
				if($key =~ /^#?args\.(.*)$/)
				{
					$query_args{$key} = $req->{$key};
					$arg_hash{$1}     = $req->{$key};
				}
			}
		}

		#die Dumper \%query_args, $req;

		# Build pagination URL for use in building links
		my $pagination_url_base = undef;
		if(!$self->output_format ne 'xls' &&
		   !$self->{disable_paging})
		{
# 			my $url_args =
# 				join '&',
# 				map {
# 					url_encode($_) .'='. url_encode($req->{$_})
# 				}
# 				grep { $_ ne 'start' && $_ ne 'length' }
# 				keys %{$req || {}};

			my $url_args =
				join '&',
				map {
					url_encode($_) .'='. url_encode($query_args{$_})
				}
				keys %query_args;

			$pagination_url_base = $req->page_path
				. ($url_args ? '?' : '')
				. $url_args;

		}

		# Do the report
		my $output_data = $self->generate_report(
			# arguments
			\%arg_hash,

			# ignore incomplete
			undef,

			# enable paging - this will be undef if output_format not HTML
			$pagination_url_base,

			# If true, only compiles arg hash, doesn't execute SQL or certain data hooks
			$disable_render
		);

		# Output the data
		if($self->output_format eq 'html')
		{
			my $tmpl = $self->tmpl;

			$output_data->{query_args} = \%query_args;
			$output_data->{query_args_json} = encode_json(\%query_args);

			unless($report->{disable_xls_export})
			{
				my $url_args =
				join '&',
				map {
					url_encode($_) .'='. url_encode($query_args{$_})
				}
				keys %query_args;

				my $faux_file = $report->{title};
				$faux_file =~ s/[^A-Za-z0-9]//g;

				if($report->{xls_filename_formatter})
				{
					$faux_file = $report->{xls_filename_formatter}->($report, $faux_file);
				}
				else
				{
					my @name_parts;

					my $arg_meta = $report->{args};

					foreach my $arg_ref (@{$arg_meta || []})
					{
						next if $arg_ref->{hidden};

						if(defined $arg_ref->{value})
						{
							my $value = $arg_ref->{value};

							if($arg_ref->{linked})
							{
								$value = $arg_ref->{linked}->stringify($value);
							}

							$value =~ s/[^A-Za-z0-9]//g;

							push @name_parts, $value;
						}
					}

					#die Dumper $arg_meta, $report if $report->{abs_file} =~ /prod_sold/;

					$faux_file .= '_'.join('-', @name_parts);
				}

				$faux_file .= '.xls';

				my $xls_url = $req->page_path
					. '/'
					. $faux_file
					. ($url_args ? '?' : '')
					. $url_args;

				$xls_url .= $xls_url =~ /\?/ ? '&' : '?';
				$xls_url .= 'output_fmt=xls';

				$output_data->{xls_url} = $xls_url;
			}

			#die Dumper $output_data->{xls_url}, $report->{args};


			$tmpl->param('report_'.$_ => $report->{$_})
				foreach keys %$report;

			$tmpl->param('report_'.$_ => $output_data->{$_})
				foreach keys %$output_data;

			if($output_data->{arg_data_complete})
			{
				#die Dumper \@report_columns, \@report_data, \@arg_data;
			}
			else
			{
				print STDERR "Not executing report yet because arg data is incomplete\n";
				#die "Not enough data";
			}

			#die Dumper $output_data, $report;

			$tmpl->param(view_message => $self->{msg});

			my $out = AppCore::Web::Form->post_process($tmpl, {
				args	     	=> \%arg_hash,
				validate_url	=> $self->{validate_url} || '/validate',
			});

			return $out;
		}
		elsif($self->output_format eq 'xls')
		{
			# TODO
			die "Excel export disabled for this report"
				if $report->{disable_xls_export};

			use Spreadsheet::WriteExcel;
			use File::Slurp;

			my $tmp_file = "/tmp/report-tmp-$$.xls";
			my $workbook = Spreadsheet::WriteExcel->new($tmp_file);

			# Add a worksheet
			my $worksheet_name = $report->{xls_sheet_name};
			if(!$worksheet_name)
			{
				if($report->{xls_filename_formatter})
				{
					$worksheet_name = $report->{xls_filename_formatter}->($report, undef);
				}
				else
				{
					my @name_parts;

					my $arg_meta = $report->{args};

					foreach my $arg_ref (@{$arg_meta || []})
					{
						next if $arg_ref->{hidden};

						if(defined $arg_ref->{value})
						{
							my $value = $arg_ref->{value};

							if($arg_ref->{linked})
							{
								$value = $arg_ref->{linked}->stringify($value);
							}

							push @name_parts, $value;
						}
					}

					$worksheet_name = join(' - ', @name_parts);
				}
			}

			my $worksheet = $workbook->add_worksheet(substr($worksheet_name,0,30));

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

			my $y = 0;
			my $x = 0;

			if($report->{enable_legacy_xls_header_rows})
			{
				$worksheet->write($y, $x++, $report->{title}, $fmt_bold)
					if $report->{title};

				$x=0;
				$y++;

				# Optionally add date, turned off for now
				#$worksheet->write($y,$x++,'Date: ');
				#$worksheet->write($y,$x++,AppCore::Common::date(),$fmt_bold);

				# TODO: Turn this off?
				$worksheet->insert_image(0,4, $report->{logo_image_file})
					if $report->{logo_image_file};

				$y++;
				$y++;

			}

			my @cols = @{ $output_data->{columns} || [] };

			#print STDERR Dumper \@cols;

			# Write a formatted and unformatted string, row and column notation.
			$x=0;
			foreach my $col (@cols)
			{
				$worksheet->write($y, $x++, $col->{title}, $hdr2);

				# ($fm->{td_align} eq 'center') ? $hdr1 : $hdr2);
			}

			$y++;
			$worksheet->freeze_panes($y, 0); # 1 row

			my $fmter = $report->{xls_column_formatter};

			my @data = @{$output_data->{data} || []};

			my $count = 0;
			foreach my $row (@data)
			{
				$x=0;
				foreach my $col_hash (@cols)
				{
					my $value =
					 exists $row->{$col_hash->{field}}    ?
						$row->{$col_hash->{field}}    :
						$row->{lc($col_hash->{field})};

					$value =~ s/<[^\>]+>//g;

					$worksheet->write($y, $x++, $fmter ? $fmter->($self, $value, $row, $col_hash->{field}) : "".$value);
				}
				$y++;
			}

			$workbook->close;

			my $tmp =  read_file( $tmp_file, binmode => ':raw' );

	 		unlink($tmp_file);

	 		return $tmp;
		}
		elsif($self->output_format eq 'json')
		{
			return $output_data;
		}
		else
		{
			die "Unknown output format";
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


};

1;

__DATA__

# Sample report model:

{
	title => 'Exam Counts by Patient',

	# Instead of giving an sql arg, could we give a 'data' arg wich is either an ARRAY ref or a CODE ref?
	# CODE refs could return an ARRAY ref and still be passed a list of args ...?
	sql => q{
		set @setupid = ?;

		select p.patientid,
			first,
			last,
			count(examid) as count
		from patients p
			left join exams x on x.patientid=p.patientid
		where
			p.officeid = ? and
			(case when @setupid is null then 1 else
				(case when x.examsetupid = @setupid then 1 else 0 end)
			end) = 1


		group by patientid, first, last
		order by first, last

	},

	# If columns NOT specified, the report code will inspect the result set to
	# find the order the columns were returned in.
	# If using the 'data' coderef instead of SQL, the report code expects an array
	# of ($data_listref, $columns_listref) to be returned. If just a $data_listref
	# is returned, it will display the columns sorted in alphabetical order.
	# columns => [
	#	{
	#		field	=> 'patientid',
	#		title	=> 'Patient',
	#	},
	# ],

	args =>
	[
		{
			field => 'examsetupid', # field is used in the UI - autogenerated if no field name givne
			title => 'Exam Type', # Title can be guessed from the title of the linked class or the field if not given explicitly
			linked => 'NCS::ExamSetup', # if 'linked' given, a 'type' arg is expected to specify what type of UI input is needed (such as date, etc)
			#type => 'int',
			#fk_constraint => '', # SQL can be given in the form of a where clause (no WHERE need) to limit the vaulues returned from the linked class
			value => 1, # could be a coderef to get the default value, or a hashref with an 'sql' arg to execute...
		},

		{
			value => $class->stash->{office},
			hidden => 1,
		},
	],

	row_mudge_hook => sub {
		my ($row) = @_;

		my $patient = NCS::Patient->retrieve($row->{patientid});
		my $url = $patient->url;

		foreach my $key (qw/patientid first last/)
		{
			$row->{$key} = '<a href="'.$url.'">' . $row->{$key} . '</a>';
		}

		# ...
	},
};


##############

<!-- Sample report viewer template -->

<title>%%report_title%%</title>

<div class='body_content_panel'>

	<form action='%%post_url%%' method='POST' id='report-form'>

		<div class="panel visit-panel panel-default">

			<div class='panel-heading clearfix'>
				<h2 class='panel-title pull-left' style='padding-top:7.5px'>
					%%report_title%%
				</h2>
				<div class="btn-group pull-right">

					<!-- TODO: Add an 'export' option here -->

					<tmpl_if report_data_count>
						<p>Displaying <b>%%report_data_count%%</b> rows of data.</p>
					</tmpl_if>
				</div>
			</div>

			<!-- Form options - arguments requested -->
			<div class='panel-body form-table'>

				<!-- Transient message - not used yet, just keeping here if we want it -->
				<tmpl_if view_message>
					<div class='alert alert-info panel-message'><tmpl_var view_message></div>
					<script>
					$(function() {
						setTimeout(function() {
							$('.panel-message').hide('fast');// 1000 );
						}, 30 * 1000);
					});
					</script>
				</tmpl_if>



				<f:form uuid='report-viewer-%%user_userid%%' id='report' class='report-args'>
					<tmpl_loop report_args>
						<tmpl_unless hidden>
							<input bind='#args.%%field%%' label='%%title%%' type-hint='%%type_hint%%' type='%%type%%' class='%%linked%%' choices='%%choices%%' size='%%size%%' placeholder='%%placeholder%%' min='%%min%%' max='%%max%%'/>
						</tmpl_unless>
					</tmpl_loop>

					<button class='btn btn-primary get-report-btn'>Get Report</button>
				</f:form>

				<script>
				$(function() {
					$('.report-args input').on('change', function() {
						//$('.schedule-status-text').html($(this).val());

						var $spin = $('<i class="fa fa-spin fa-spinner" style="display:inline-block;margin:0 1rem;margin-top:8px"></i>');
						$spin.insertAfter($('.get-report-btn'));

						$('#report-form').submit();
					});

					$('.report-args input').first().focus();
				});
				</script>

			</div> <!-- /.panel-body -->

			<!-- Actual report data -->
			<div class='table-responsive'>

				<!-- This div is used by CSS to cast a faux shadow over the lines on the left & right when in 'responsive' mode (sub 768px width) or whatever CSS is set to -->
				<div class='table-responsive-shadow'></div>

				<table class="report-data table table-hover table-bordered " style='width:100%'><!--table-condensed table-striped -->
					<thead>
						<tmpl_loop report_columns>
							<th>%%title%%</th>
						</tmpl_loop>
					</thead>
					<tbody>
						<tmpl_loop report_data>

							<tr class='report-data-row'>
								<tmpl_loop report_columns>
									<td class='report-data-cell col-%%field%%'>
										<span class='value'>%%value%%</span>
									</td>
								</tmpl_loop>
							</tr>

						</tmpl_loop>
					</tbody>
				</table>
			</div><!--/.table-responsive-->

			<tmpl_if report_data_count>
				<div class='panel-footer form-table'>

					<p>Displaying <b>%%report_data_count%%</b> rows of data.</p>

					<!--<div class='form-button-wrapper'>

						TODO: Add export options here

					</div>-->
				</div>
			</tmpl_if>
		</div><!--/.panel-->

	</form>
</div>
