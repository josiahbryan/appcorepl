use strict;
package Content;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	use Content::Page;
	
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
		
		if(!$self->process_page($req,$r))
		{
			my $url = AppCore::Web::Common->get_full_url();
			return $r->error("Unknown Page Address","The page requested does not exist: <b>$url</b>");
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
		
		# Try to get the database entry for the current URL 
		my $page_obj = $self->get_page($req->page_path);
		
		#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.", obj? $page_obj\n";
		
		# If entry is valid, process it
		if($page_obj)
		{
			#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": next_page_path: ".$req->next_page_path."\n";
			
			# Before just processing this page, check to see if the
			# next page in the URL is valid, if so, process it instead
			if($req->next_page_path && 
			   $self->get_page($req->next_page_path))
			{
				# If the next page path is valid, push the next path element onto the page path
				# so that the call to process_page() loads the right url
				$req->push_page_path($req->shift_path);
				
				$self->process_page($req,$r);
				return 1;
			}
			else
			
			# Next page not valid, process this page
			{
				my $type = $page_obj->typeid;
				#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": type: $type\n";
				if($type && $type->id)
				{
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
		}
		
		return 0;
		
		#my $cur_page  = $req->last_path;
		#my $next_path = $req->next_path;
		
# 		print STDERR "SitePage: next_path: $next_path\n";
# 		print STDERR Dumper $req;
# 		
# 		return $r->output("$cur_page: $next_path");
		
		
		
	};
	
	

};

1;
