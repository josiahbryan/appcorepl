use strict;

package PHC::SearchHook;
{
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> AppCore::Config->get("SEARCH_HOOK_DBTABLE") || 'search_hooks',
		
		schema	=> 
		[
			{ field => 'hookid',		type	=> 'int', @AppCore::DBI::PriKeyAttrs },
			{ field	=> 'controller',	type	=> 'varchar(255)' },
			{ field	=> 'method',		type	=> 'varchar(255)' },
			{ field	=> 'is_enabled',	type	=> 'int(1)', null=>0, default => 1 },
		],	
	});
	
	our %PacakgeCodeRefs;
	
	sub register
	{
		my $filter_ref = undef;
		undef $@;
		eval
		{
			my $pkg = shift;
			$pkg = ref $pkg if ref $pkg;
			
			my $method   = shift || 'search_hook';
			my $code_ref = shift || undef;
			
			$filter_ref = __PACKAGE__->find_or_create({controller=>$pkg, method=>$method});
			
			$PacakgeCodeRefs{$pkg} = $code_ref if $code_ref;
			
		};
		warn $@ if $@;
		
		return $filter_ref;
	}
	
	sub hook
	{
		my $self = shift;
		my $event = shift;
		my $args = shift;
		
		my $pkg = $self->controller; #ref $self ? ref $self : $self;
		
		# Default impl of hook() calls any code refs for this package, if present, otherwise calls $pkg->method
		my $code_ref = $PacakgeCodeRefs{$pkg};
		if($code_ref)
		{
			return &{$code_ref}($event,$args);
		}
		else
		{
			my $method = $self->method;
			my $obj = $pkg; #AppCore::Web::Module->bootstrap($pkg);
			
			#print STDERR __PACKAGE__."::hook: pkg:'$pkg', ref:'$obj', event:'$event'\n";
			return $obj->$method($event, $args);
		}
		
		return 1;
	}
}


package PHC::SearchHook::ContentSearch;
{
	use ThemePHC::Search;
	use base 'PHC::SearchHook';
	__PACKAGE__->register();
	
	use AppCore::Web::Common;
	
	use Content::Page;
	
	sub search_hook
	{
		my ($class,$event,$args) = @_;
		
		if(!Content::Page->can('search_like_titles'))
		{
			Content::Page->add_constructor(search_like_titles => 'title like ? or content like ?'); # if !Content::Page->can('search_group_type');
		}
		
		if($event eq 'autocomplete' || $event eq 'search')
		{
			my $term = $args->{term};
			my $like = '%' . $term . '%';
			my @pages = Content::Page->search_like_titles($like,$like);
			
			my @results = map 
			{
				{
					title	 => $_->title,
					body	 => html2text($_->content),
					url	 => $_->url,
					timestamp => $_->timestamp,
				}
			} @pages;
			
			if($event eq 'autocomplete')
			{
				@results = grep { $_->{title} =~ /$term/ } @results ;
				#die Dumper [$term, \@pages];
			}
			
			my $ref = \@results;
			return $ref;
		}
	}
};

package PHC::SearchHook::Boards;
{
	use ThemePHC::Search;
	use base 'PHC::SearchHook';
	__PACKAGE__->register();
	
	use AppCore::Web::Common;
	
	use Boards::Data;
	
	sub search_hook
	{
		my ($class,$event,$args) = @_;
		
		my $sth = Boards::Post->db_Main->prepare(qq{
				select p.postid, 
					p.boardid,
					p.poster_name,
					p.timestamp,
					unix_timestamp() - unix_timestamp(p.timestamp) as timediff,
					p.subject,
					p.text,
					p.folder_name,
					p.ticker_class,
					boards.folder_name as `board_folder_name`,
					boards.section_name,
					boards.title as `board_title`
					
				from board_posts p, boards 
				
				where p.deleted=0 and p.hidden=0 and
				      p.boardid = boards.boardid and
				      (p.subject like ? or p.text like ? or p.poster_name like ?)
				
				order by timestamp desc
			});
		
		
		if($event eq 'autocomplete' || $event eq 'search')
		{
# 			my $like = '%' . $args->{term} . '%';
# 			my @pages = Content::Page->search_like_titles($like,$like);
# 			
# 			my @results = map 
# 			{
# 				{
# 					title	 => $_->title,
# 					body	 => html2text($_->content),
# 					url	 => $_->url,
# 					timestamp => $_->timestamp,
# 				}
# 			} @pages;
			
			#my $ref = \@results;
			#return $ref;
				
			my $bin = '';#PHC::Web::Context->http_bin;
			my $short_len = 255;
			my $subject_len = 255;
			my $board_len = 15;
			my @list;
			
			my $q = $args->{term};
			
			$sth->execute('%'.$q.'%','%'.$q.'%','%'.$q.'%');
			#if(!$sth->rows)
			#{
			#	$sth->finish;
			#	$range = 30 * 60 * 60 * 24;
			#	$sth->execute($range);
			#}
			
			while(my $post = $sth->fetchrow_hashref)
			{
				#$post->{sth}			= $sth;
				$post->{bin} 			= $bin;
				$post->{short_text} 		= html2text($post->{text});
				$post->{short_text} 		= encode_entities(substr($post->{short_text},0,$short_len) . (length($post->{short_text}) > $short_len ? '...' : ''));
				$post->{short_text} =~ s/($q)/<b class="match-highlight">$1<\/b>/gi if $q;
				$post->{'section_'.$post->{section_name}} = 1;
				$post->{'folder_'.$post->{folder_name}} = 1;
				$post->{'ticker_class_'.$post->{ticker_class}} = 1;
				$post->{board_title_short}	= substr($post->{board_title},0,$board_len) . (length($post->{board_title}) > $board_len ? '...' : '');
				$post->{board_title} 		= encode_entities($post->{board_title});
				$post->{subject_short}		= encode_entities(substr($post->{subject},0,$subject_len) . (length($post->{subject}) > $subject_len ? '...' : ''));
				$post->{subject} 		= encode_entities($post->{subject});
				$post->{min_ago}		= $post->{timediff} / 60;
				$post->{approx_hrs_ago}		= int($post->{min_ago} / 60);
				$post->{time_ago} 		= to_delta_string($post->{min_ago});
				
				#$class->rss_filter_list_hook($post);
				
				push @list, $post;
			}
			
			#die Dumper \@list;
			my @results;
			foreach my $post (@list)
			{
				push @results, 
				{
					title	 => $post->{board_title_short}.': '.$post->{subject},
					body	 => html2text($post->{text}),
					#url	 => "/boards/$post->{folder_name #join('/', $bin, $post->{section_name}, $post->{folder_name}, $post->{fake_folder_name}),
					url	 => "/boards/$post->{board_folder_name}/$post->{folder_name}",
					time_ago => $post->{time_ago},
					author   => $post->{poster_name},
					timestamp=> $post->{timestamp},
				};
			}
			
			#die Dumper \@list;
			
			return \@results;
		}
	}
};

package ThemePHC::Search;
{
	# Inherit both the AppCore::Web::Module and Page Controller.
	# We use the Page::Controller to register a custom
	# page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	use Content::Page;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Search/Log Page','Provides searching and "Activity Log" facilities for ThemePHC',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	#use DateTime;
	use AppCore::Common;
	use AppCore::Web::Common;
	use JSON qw/encode_json/;
	
#	my $MGR_ACL = [qw/Pastor/];
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::SearchHook
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		return $self;
	};
# 	
	# Implemented from Content::Page::Controller
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = AppCore::Config->get("DISPATCHER_URL_PREFIX") . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		return $self->search_page($req,$r);
	};
	
	our %ResultsCache;
	our %ProcessedCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing cached data...\n";
		%ResultsCache = ();
		%ProcessedCache = ();
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	sub run_hooks
	{	
		my $self = shift;
		my $event = shift;
		my $args = shift;
		
		my $key = join(':',$event,( $event eq 'log' ? $args->{window} : $args->{term} ));
		
		return $ResultsCache{$key} if $ResultsCache{$key};
		#print STDERR __PACKAGE__."::run_hooks: Cache miss for '$key'\n";
		
		my @result_list;
		my @hooks = PHC::SearchHook->search(is_enabled => 1);
		foreach my $hook (@hooks)
		{
			undef $@;
			my $result;
			eval { $result = $hook->hook($event,$args); };
			#die Dumper $result, $ctrl, $event, $args ;
				
			#$hook->hook($event, $args);
			warn "Problem running search action hookid $hook from controller ".$hook->controller." for '$event': ".$@ if $@;
			push @result_list, @{ $result || [] };
		}
		
		return $ResultsCache{$key} = \@result_list;
	}
	
	sub search_page
	{
		my $self = shift;
		my ($req,$r) = @_;
		
 		my $user = AppCore::Common->context->user;
			
		my $term = $req->term || $req->q;
		if($term)
		{
			# strip tags to try to prevent cross-domain hacks
			$term=~s/<([^>]|\n)*>//g;
			
			# replace *s and ?s with % to enable matching by the "like" sql statement
			$term=~s/\s*[\*\?]\s*/%/gi;
			
			# due to the regex usage in matching searches, a single bar or other special characters can hoze the server
			$term=~s/\s[\|\.\*\+\$\^\\]\s/ /g;
		}
		
		my $sub_page = $req->next_path;
		
		if($sub_page eq 'autocomplete')
		{
			my $results = $self->run_hooks('autocomplete', { term => $term });
			
			$self->process_results($results, $term, 'autocomplete');
			
			# Grab up to the first 50 results 
			my @slice = @{$results || []};
			my $max = scalar @slice;
			$max = $max > 50 ? 50 : $max;
			@slice = @slice[0..$max];
			
			# Convert to label/id pairs for use by the jQuery autocomplete scripts
			$results = [ map { $_->{label} = $_->{title}; $_->{id} = $_->{url}; $_ } @slice ];
			
			# Sort by rating - then by title
			$results = [ sort { $b->{rating} <=> $a->{rating} || $a->{title} cmp $b->{title} } @$results ];
			
			# Send back as json
			my $json = encode_json($results);
			return $r->output_data("application/json", $json);
		}
		elsif($sub_page eq 'log')
		{
			# Still TODO
			my $window = $req->window || 2; # window size always in days
			my $results = $self->run_hooks('log', { window => $window });
			
			my $tmpl = $self->get_template('search/log.tmpl');
			$tmpl->param(results => $results);
			return Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			
		}
		else # plain search page
		{
			my $tmpl = $self->get_template('search/search_results.tmpl');
			
			my $term = $term;
			if($term && length($term) > 1)
			{
				use Time::HiRes qw/time/; 
				
				my $time_a = time;
				
				my $results = $self->run_hooks('search', { term => $term });
				$self->process_results($results, $term, 'search');
				
				if($req->{sortby} eq 'timestamp')
				{
					$tmpl->param(sortby_timestamp => 1);
					$results = [ sort { $b->{timestamp} cmp $a->{timestamp} || $b->{rating} <=> $a->{rating} || $a->{title} cmp $b->{title} } @$results ];
				}
				else
				{
					$tmpl->param(sortby_relevance => 1);
					$results = [ sort { $b->{rating} <=> $a->{rating} || $a->{title} cmp $b->{title} } @$results ];
				}
				
				
				#die Dumper $results;
				$tmpl->param(results => $results);
				$tmpl->param(term => $req->term || $req->q);
				$tmpl->param(page_list_size => scalar @$results);
				
				my $time_b = time;
				my $diff = $time_b - $time_a;
				
				$tmpl->param(time => sprintf('%.04f',$diff));
			}
			
			return Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		}
	}
	
	sub process_results
	{
		my $self = shift;
		my $results = shift || [];
		my $q = shift;
		my $event = shift || 'search';
		
		my $key = join(':',$event, $q);
		
		return $ProcessedCache{$key} if $ProcessedCache{$key};
		
		$q=~s/\s/\./g;
		
		my $sz = 75;
			
		#die Dumper $results;
		
		$results = [ grep { $_->{title} } @$results ];
		
		foreach my $line (@$results)
		{
			# Extract snippet from {body} for the search term
			my $idx = index(lc $line->{body},lc $q);
			my $start = $idx - $sz;
			$start = 0 if $start < 0;
			my $len = length($q) + $sz * 2;
			$len = length($line->{body}) - $start if $len + $start > length($line->{body});
			
			my $past_end = $len + $start < length($line->{body});
			my $past_start = $start > 0;
			
			#print STDERR "idx=$idx, start=$start, len=$len, past_start=$past_start, past_end=$past_end, q='$q'\n"; #, body=$line->{body}\n";
			
			$line->{non_fuzz} = $line->{body};
			$line->{non_fuzz} =~ s/[^\w\d\.\?\!]//g;
			$line->{body} = ($past_start ? "<b>...</b>" : "").substr($line->{body},$start,$len) . ($past_end ? "<b>...</b>" : "");
			#$line->{body} .= " (<a href='$line->{url}'>Go to page</a>)" if $past_start || $past_end;
			
			# Calculate a rating based on the search query
			my @count_body = $line->{body} =~ /($q)/i;
			my @count_title = $line->{title} =~ /($q)/i;
			my @count_url = $line->{url} =~ /($q)/i;
			
			my $count_body = scalar @count_body;
			my $count_title = scalar @count_title;
			my $count_url = scalar @count_url;
			
			#die Dumper $count_body, $count_title, $count_url, .25 * (length($line->{non_fuzz}) / 1024) if $line->{url} =~ /merry_christmas/;
			
			$line->{rating} = sprintf('%.00f%',(1 * scalar(@count_url) + .95 * scalar(@count_title) + .75 * scalar(@count_body) + .25 * (length($line->{non_fuzz}) / 1024)  ) / 3.25 * 100) ;
			
			# Perform final highlighting and processing of results
			$line->{display_url} = $line->{url};
			
			if($event eq 'search')
			{
				$line->{body} =~ s/($q)/<b class="match-highlight">$1<\/b>/gi if $q;
				$line->{title} =~ s/($q)/<b class="match-highlight">$1<\/b>/gi if $q;
				$line->{display_url} =~ s/($q)/<b class="match-highlight">$1<\/b>/gi if $q;
				
				$line->{body} = Boards::TextFilter::TagVerses::replace_block($line->{body});
			}
			else
			{
				$line->{$_} = html2text($line->{$_}) foreach qw/body title url/;
			}
		}
		
		return $ProcessedCache{$key} = $results;	
	}
	
	
}



1;