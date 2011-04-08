use strict;
package Content;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	use Content::Page;
	use Content::Admin;
	
	sub DISPATCHER_METHOD { 'main'}
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		dump_request 
	/);
	 
	sub apply_mysql_schema
	{
		Content::Page->apply_mysql_schema;
	}
	
	sub new
	{
		my $class = shift;
		# constructor here just for the heck of it
		# No guarantees how long the object will live
		# If no constructor present, then the methods will just be called individually, unless the $DISPATCHER_METHOD is set.
		
		# Even if a constructor is present, the DISPATCH_METHOD will be called - just on the blessed ref
		
		return bless {}, $class;
	};
	
	
	sub main
	{
		my $self = shift;
		my $req = shift;
		my $r = AppCore::Web::Result->new;
		
		# Handle /content/admin/ URLs internally
		if($req->last_path eq 'content' &&
		   $req->next_path eq 'admin')
		{
			# Move admin into the page_path list
			$req->push_page_path($req->shift_path);
			
			# Use AppCore::Web::Module::dispatch() to re-dispatch the request into the Content::Admin module
			return $self->dispatch($req, 'Content::Admin');
			
		}
		
		if(!$self->process_page($req,$r))
		{
			my $url = AppCore::Web::Common->get_full_url();
			#return $r->error("Unknown Page Address","The page requested does not exist: <b>$url</b>");
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			
			my $tmpl = $self->get_template("bad_url.tmpl");
			#$tmpl->param(bad_url => AppCore::Web::Common->encode_entities($url));
			$tmpl->param(bad_url => $url);
			
			$view->output($tmpl);
		}
		
		return $r;
	}
	
	sub dump_request 
	{
		my $self = shift;
		my $req = shift;
		my $r = AppCore::Web::Result->new;
		
		return $r->output("<pre>".Dumper($req)."</pre>");
	}
	
	
	sub get_page
	{
		my $self = shift;
		my $url  = shift;
		my $obj = $self->{page_obj_cache}->{$url};
		
		#print STDERR __PACKAGE__ . "::get_page(): url:'$url'\n'";
		
		$obj = $self->{page_obj_cache}->{$url} 
		     = Content::Page->by_field(url => $url) 
		     if !$obj;
		
		return $obj;
	}
	
	sub process_page
	{
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		
		my @url = split /\//, join('/', $req->page_path, $req->path);
		
		@url = '/' if !@url;
		
		# Basic sanity check
		@url = @url[0..$AppCore::Config::MAX_URL_DEPTH] if @url > $AppCore::Config::MAX_URL_DEPTH;
		
		# reset page path and path info
		$req->page_path(join '/', @url);
		$req->path('');
		
		my $popped = 0;
		
		while(@url)
		{
			my $cur_url = join('/', @url);
			#print STDERR __PACKAGE__."::process_page(): Testing '$cur_url'...\n";
		
			# Try to get the database entry for the current URL 
			my $page_obj = $self->get_page($cur_url);
			
			if($page_obj)
			{
				$req->page_path($cur_url);
				#print STDERR __PACKAGE__."::process_page(): Got valid pageid $page_obj for '$cur_url', sending!\n";
				
				# Found valid page, output
				my $type = $page_obj->typeid;
				#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": type: $type\n";
				if($type && $type->id)
				{
					if($popped && $type->id == 1) # static page, ignores page path, so original URL was what user wanted
					{
						return 0;
					}
					
					# Other page types might use page path, so allow to process normally
					
					# Calls $r->output itself as needed
					$type->process_page($req,$r,$page_obj);
				}
				else
				{
					# Output the raw content if no view set
					Content::Page::Type->failover_output($r,$page_obj)
				}
				return 1;
			}
			else
			{
				# Chop end off url and reprocess
				my $pp = pop @url;
				$req->unshift_path($pp);
				$popped = 1;
				#print STDERR __PACKAGE__."::process_page(): '$cur_url' didnt match, popped $pp, retrying...\n";
			}
			
		}
		return 0;
	};
	
	

};

1;
