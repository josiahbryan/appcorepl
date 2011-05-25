use strict;
package Content;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	use Content::Page;
	use Content::Admin;
	
	# To auto-redirect to a post...
	use Boards::Data;
	
	use Admin::ModuleAdminEntry;
	#Admin::ModuleAdminEntry->register(__PACKAGE__);
	Admin::ModuleAdminEntry->register(__PACKAGE__, 'Pages', 'content', 'List all pages on this site, and create/update/delete pages.');
	
	sub DISPATCHER_METHOD { 'main'}
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		dump_request
		sitemap 
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
		my $r = shift;
		
		# Handle /content/admin/ URLs internally
		if($req->last_path eq 'content' &&
		   $req->next_path eq 'admin')
		{
			# Move admin into the page_path list
			$req->push_page_path($req->shift_path);
			
			# Use AppCore::Web::Module::dispatch() to re-dispatch the request into the Content::Admin module
			#return $self->dispatch($req, 'Content::Admin');
			
			# Moved the Admin module to an Admin plugin
			return $r->redirect('/admin/content/'.join('/', $req->path_info).'?'.$ENV{QUERY_STRING});
			
		}
		
		if(!$self->process_page($req,$r))
		{
			my $url = AppCore::Web::Common->get_full_url();
			
			my $trim = $url;
			$trim =~ s/^\///g;
			if(index($trim, '/') < 0)
			{
				my $post = Boards::Post->by_field(folder_name => $trim);
				if($post && $post->id)
				{
					my $url = Boards->module_url($post->boardid->folder_name . "/" . ($post->folder_name ? $post->folder_name : $post->id));
					#print STDERR "Auto-redirecting fallthru to post $post, url: $url\n";
					return $r->redirect($url);
				}
			}
			
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
		my $r = shift;
		
		return $r->output("<pre>".Dumper($req)."</pre>");
	}
	
	sub sitemap
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $tmpl = $self->get_template('sitemap.tmpl');
		$tmpl->param(nav => Content::Page::ThemeEngine->load_nav);
		
		my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		
		return $r;
	}
	
	our %LiveObjects;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing page_obj_cache...\n";
		foreach my $obj (values %LiveObjects)
		{
			$obj->{page_obj_cache} = {};
		}
		%LiveObjects = ();
	}	
	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	sub get_page
	{
		my $self = shift;
		my $url  = shift;
		my $mobile_flag = shift || 0;
		my $cache_key = "$url.$mobile_flag";
		my $obj = $self->{page_obj_cache}->{$cache_key};
		return $obj if $obj;
		
		my $field = $mobile_flag ? 'mobile_alt_url' : 'url';
		
# 		print STDERR __PACKAGE__ . "::get_page(): url:'$url', field: $field, mobile_flag: $mobile_flag, cache key: $cache_key\n'";
# 		use Data::Dumper;
# 		print STDERR Dumper $self->{page_obj_cache};
		
		$obj = $self->{page_obj_cache}->{$cache_key} 
		     = Content::Page->by_field($field => $url) 
		     if !$obj;
		
		# Register ourself for when we need to clear the caches
		$LiveObjects{$self} = $self if !$LiveObjects{$self};
		
		return $obj;
	}
	
	sub process_page
	{
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		
		# Reset current theme
		Content::Page::Controller->theme($AppCore::Config::THEME_MODULE);
		
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
				#print STDERR __PACKAGE__."::process_page(): Got valid pageid $page_obj for '$cur_url'\n"; #, sending!\n";
				
				# Honor the 'mobile_alt_url' field in Content::Page
				if(AppCore::Common->context->mobile_flag)
				{
					# If mobile page available for this URL, then redirect there
					if($page_obj->mobile_alt_url &&
						$page_obj->mobile_alt_url ne $page_obj->url)
					{
						return $r->redirect($page_obj->mobile_alt_url);
					}
				}
				else
				{
					# If this page IS the mobile page for another 'main' page AND this is not mobile, redirect to the other 'main' page
					my $alt_page = $self->get_page($page_obj->url,1); # get page that matches mobile_alt_url not url
					if($alt_page)
					{
						return $r->redirect($alt_page->url);
					}
				}
				
				# Honor the 'redirect' URL
				if($page_obj->redirect_url)
				{
					return $r->redirect($page_obj->redirect_url);
				}
				
				if(!$page_obj->check_acl)
				{
					die "Error: You dont have the necessary clearance to access ".$page_obj->url."\n"; 
				}
				
				
				# Found valid page, output
				my $type = $page_obj->typeid;
				#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": type: $type\n";
				if($type && $type->id)
				{
					if($popped && !$type->uses_pagepath) # static page, ignores page path, so original URL was what user wanted
					{
						return 0;
					}
					
					# Other page types might use page path, so allow to process normally
					$r->{page_obj} = $page_obj;
					
					# Calls $r->output itself as needed
					#use Data::Dumper;
					#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": type: $type, dumper:".Dumper($req)."\n";
					$type->process_page($req,$r,$page_obj);
				}
				else
				{
					return 0 if $popped;
					# Pass to default controller
					#print STDERR __PACKAGE__."::process_page(): Page Path: ".$req->page_path.": type: $type, dumper:".Dumper($req)."\n";
					Content::Page::Controller->process_page(undef,$req,$r,$page_obj);
					
				}
				return 1;
			}
			else
			{
				# Chop end off url and reprocess
				my $pp = pop @url;
				$req->unshift_path($pp);
				$req->pop_page_path();
				$popped = 1;
				#print STDERR __PACKAGE__."::process_page(): '$cur_url' didnt match, popped $pp, retrying...\n";
			}
			
		}
		return 0;
	};
	
	

};

1;
