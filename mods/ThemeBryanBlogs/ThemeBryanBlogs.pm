use strict;

package ThemeBryanBlogs;
{
	use Content::Page;
	use base qw/Content::Page::ThemeEngine 
		    Content::Page::Controller 
		    AppCore::Web::Module/;

	use Scalar::Util 'blessed';
	
# 	use ThemeBryanBlogs::FrontPage;
 	use BryanBlogs::Blog; # Class::DBI objects describing the blogs, posts, and comments
# 	use ThemeBryanBlogs::Blog::FrontPage;
# 	use ThemeBryanBlogs::PostViewer;

	our $ThemeHandle = __PACKAGE__->register_theme('Bryan Blogs','Bryan Blogs Website Theme', [qw/home admin sub mobile/]);
	
	__PACKAGE__->register_controller('Bryan Blogs','Bryan Blogs Controller',1); # 1 = uses page path
	
# 	sub apply_mysql_schema
# 	{
# 		ThemeBryanBlogs::Blog->apply_mysql_schema;
# 	}

	sub new { return bless {}, shift }
	
	__PACKAGE__->WebMethods(qw/ 
		main 
	/);
	
	sub compat_auth
	{
		my $user = AppCore::Common->context->user;
		if(!$user || !$user->data->get('bryanblogs_legacy_userid'))
		{
			# Grab legacy authentication cookie (why it's wiki/sid I don't quite know...)
			my $sid = AppCore::Web::Common->cookie('wiki/sid');
			my ($username,$response,$password) = ($sid=~/^([^\:]+)\:([^\:]*)\:(.*)$/);
			
			# Lookup user/pass in legacy DB first to get ref
			my $dbh = AppCore::DBI->dbh('pci','database','root',$BryanBlogs::Blog::DbPassword);
			if(!$dbh)
			{
				warn "Unable to connect to legacy database server, unable to finish compat_auth()";
				return;
			}
			
			# Get all data necessary to create the user (name, email, userid)
			my $sth_xref = $dbh->prepare('select e.first, e.last, e.display, u.empid as userid, u.email from pci.employees e, pci.computer_users u where e.empid=u.empid and u.user=? and u.pass=?');
			$sth_xref->execute($username,$password);
			my $result = $sth_xref->rows ? $sth_xref->fetchrow_hashref : undef;
			
			# No user, try and find or create...
			if(!$user)
			{
				# Get email, crossref with email in current user db - if not found, create, if found, just set $user
				my $email = $result->{email};
				
				# If user exists, nothing else needed other than set the legacy ID in outside block
				$user = AppCore::User->by_field(email => $email);
				
				# Oops, no user in current DB, so create using the data we pulled in from legacy
				if(!$user)
				{
					$user = AppCore::User->create({email => $email});
					$user->pass($password);
					$user->email($email);
					$user->user($username);
					$user->display($result->{display});
					$user->first($result->{first});
					$user->last($result->{last});
					$user->update;
				}
			}
			
			# Set the legacy ID for use in queries
			$user->data->set('bryanblogs_legacy_userid', $result->{userid});
			
			# Force authentication (to set a cookie) in case not authenticated
			AppCore::AuthUtil->authenticate($user->user,$user->pass);
		}
		
		return $user;
	}
	
	sub main
	{
		my ($self,$req,$r) = @_;
		
		# Check for legacy cookies and auto-create user, then authenticate() as needed
		$self->compat_auth();
		
		my $np = $req->next_path;
		
		#$view->output("<h1>Welcome!</h1><p>Were you looking for '<b>$np</b>'?");
		if(!$np)
		{
			return $self->page_frontpage($req,$r);
		}
		else
		{
			# $np is a blog folder name
			# It will dispatch from there as needed
			return $self->page_blogfolder($req,$r);
		}
		
		# Never reached...
		return $r;
	}
	
	sub load_comments
	{
		my $self = shift;
		my $post = shift;
		my $postid = $post->id;
		my $dbh = BryanBlogs::Blog->db_Main;
		my $q_comments = $dbh->prepare('select * from jblog.comments where postid=? order by timestamp asc');
		
		$q_comments->execute($postid);

		my $q_cmt_likes = $dbh->prepare('select count(lineid) as count from comment_likes where commentid=? and (userid!=? or userid is null)');
		my $q_youlike_cmt = $dbh->prepare('select count(lineid) as count from comment_likes where commentid=? and userid=?');
		my $q_cmt_other_names = $dbh->prepare('select distinct display from comment_likes p,pci.employees e where p.userid=e.empid and p.userid is not null and p.commentid=? and p.userid!=? order by display');
		
		my @list;
		
		my %depth_counter;
		my %comments_by_parent;
		
		# Comment Feature added on this date in 2009...
		my $COMMENT_FLAG_CUTOFF = '2009-03-26 17:00:00';
		
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		
		while(my $c = $q_comments->fetchrow_hashref)
		{
			my $is_new = 0; # !check_comment_read_flag($c->{commentid});
			if(($c->{timestamp} cmp $COMMENT_FLAG_CUTOFF) < 0)
			{
				$is_new = 0;
			}
			else
			{
				$is_new = !BryanBlogs::ReadFlag->check_comment_read_flag($c->{commentid});
				if($is_new)
				{
					BryanBlogs::ReadFlag->set_comment_read_flag($c->{commentid}); # unless $c->{commentid} == 6442;
				}
			}
			
			$c->{timestamp} =~ s/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/($2+0)."\/$3\/".substr($1,2,4)." $4:$5"/segi;
			$c->{postid} = $postid;
			$c->{blogid} = $post->blogid->id;
			$c->{comment} =~ s/\n/<br>\n/g;
			$depth_counter{$c->{commentid}} = $depth_counter{$c->{parentcomment}} + 1;
			my $dem = $depth_counter{$c->{parentcomment}} * 2;
			$c->{depth_em} = $dem; # == 0 ? 0 : $dem + 2;
			$c->{new_comment} = $is_new;

			$q_cmt_likes->execute($c->{commentid},$empid);
			$q_youlike_cmt->execute($c->{commentid},$empid) if $empid;

			$c->{others_like} = $q_cmt_likes->fetchrow_hashref->{count};
			$c->{you_like} = $q_youlike_cmt->fetchrow_hashref->{count} if $empid;

			$q_cmt_other_names->execute($c->{commentid},$empid);
			my @list;
			push @list, $_->{display} while $_ = $q_cmt_other_names->fetchrow_hashref;
			my $diff = $c->{others_like} - scalar(@list);
			push @list, "$diff others" if $diff > 0;
			$c->{others_like_names} = join(", ",@list);
			$c->{others_like_names_list} = join("\n", @list);
			
			$c->{parentcomment} = 0 if !$c->{parentcomment};
			push @{ $comments_by_parent{$c->{parentcomment}} }, $c;
			
			push @list, $c;
		}
		
		#die Dumper \%comments_by_parent, \%depth_counter;
		
		#$ref->{folder_name} = $blogdat->{folder_name};
		
		#$ref->{comments} = \@list;
		
		sub order_children
		{
			my $parent_id = shift;
			my $list = shift || [];
			my $hash = shift;
			my @child_list = @{$hash->{$parent_id} || []};
			foreach my $p (@child_list)
			{
				push @$list, $p;
				order_children($p->{commentid},$list,$hash);
			}
		}
		
		my @ordered_list;
		order_children('0',\@ordered_list,\%comments_by_parent);
		
		return \@ordered_list;
	}
	
	# Display a list of blogs and the first post in each blog
	sub page_frontpage
	{
		my ($self,$req,$r) = @_;
		
		my $user = AppCore::Common->context->user;
		my $binpath = $self->binpath;
		
		my @blogs = BryanBlogs::Blog->retrieve_from_sql('1 order by lastupdated desc');
		foreach my $blog (@blogs)
		{
			$blog->{$_} = $blog->get($_) foreach $blog->columns;
			my $post = $blog->latest_post;
			if($post)
			{
				my $p = $post->first_paragraph;
				$blog->{first_para} = $p;
				$blog->{'post_'.$_} = $post->get($_) foreach $post->columns;
				$blog->{binpath} = $binpath;
			}
		}
		
		
		my $view = $self->get_view('sub',$r);
		
		my $tmpl = $self->get_template('blog_frontpage.tmpl');
		$tmpl->param(blogs => \@blogs);
		
		$view->output($tmpl);
		
		return $r;
		
	}
	
	
	
	sub page_blogfolder
	{
		my ($self,$req,$r) = @_;
		
		# Check for legacy cookies and auto-create user, then authenticate() as needed
		$self->compat_auth();
		
		my $blog_folder = $req->next_path;
		
		# Push the current path (the blog name) onto the page path list
		$req->push_page_path($blog_folder);
		
		my $blog = BryanBlogs::Blog->by_field( folder_name => $blog_folder );
		if(!$blog)
		{
			return $r->error('No Blog','No blog matches the requested folder');
		}
		
		if($blog->auth_required && !AppCore::Common->context->user)
		{
			return $r->error('Authentication Required',"Sorry, you must be logged in to view this blog, per the blog author's required.");
		}
		
		my $post_folder = $req->next_path;
		if(!$post_folder)
		{
			return $self->page_blog_frontpage($req,$r,$blog);
		}
		else
		{
			return $self->page_blog_postviewer($req,$r,$blog);
		}
	}
	
	sub page_blog_frontpage
	{
		my ($self,$req,$r,$blog) = @_;
		
		my $binpath = $self->binpath;
		
		my $binpath_page = $binpath . '/' . $blog->folder_name;
		
		my @posts = BryanBlogs::Post->retrieve_from_sql('blogid=? and draft_flag="no" order by postdate desc');
		foreach my $post (@posts)
		{
			$post->{$_} = $post->get($_) foreach $post->columns;
			$post->{binpath} = $binpath;
			$post->{binpath_page} = $binpath_page;
			#$post->{first_para} = $post->first_paragraph;
		}
		
		my $view = $self->get_view('sub',$r);
		
		my $tmpl = $self->get_template('blog_blogpage.tmpl');
		$tmpl->param(posts => \@posts);
		$tmpl->param('blog_' . $_ => $blog->get($_)) foreach $blog->columns;
		
		$view->output($tmpl);
		
		return $r;
	}
	
	sub page_blog_postviewer
	{
		my ($self,$req,$r,$blog) = @_;
		
		my $post_folder = $req->next_path;
		my $post = BryanBlogs::Post->by_field( folder_name => $post_folder );
		if(!$post)
		{
			return $r->error('No Post','No posts match the requested folder');
		}
		
		my $view = $self->get_view('sub',$r);
		
		my $tmpl = $self->get_template('blog_postviewer.tmpl');
		
		my $binpath = $self->binpath;
		my $binpath_page = $binpath . '/' . $blog->folder_name . '/' . $post_folder;
		
		$tmpl->param(page_binpath => $binpath_page);
		$tmpl->param('post_' . $_ => $post->get($_)) foreach $post->columns;
		$tmpl->param('blog_' . $_ => $blog->get($_)) foreach $blog->columns;
		
		$tmpl->param(content => $post->get_content);
		
		$view->output($tmpl);
		
		return $r;
	}
	
	
	
	
	# Implemented from Content::Page::Controller
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# No view code will just return the BasicView derivitve which just uses the basic.tmpl template
		my $view_code = $page_obj ? $page_obj->view_code : undef;
		
		# Set the current theme to be used by the get_view() method
		$self->theme(__PACKAGE__);
		
		#print STDERR "process_page: view_code is '$view_code', type: $type_dbobj\n";
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = $AppCore::Config::DISPATCHER_URL_PREFIX . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		return $self->dispatch($req, $r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
	# Implemented from Content::Page::ThemeEngine
	#
	# The output() routine is the core of the Theme - it's where the theme applies the
	# data from the Content::Page object and any optional $parameters given
	# to the HTML template and sends the template out to the browser.
	# The template chosen is (should be) based on the $view_code requested by the controller.
	sub output
	{
		my $self       = shift;
		my $page_obj   = shift || undef;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $parameters = shift || {};
		
		my $tmpl = undef;
		#print STDERR __PACKAGE__."::output: view_code: '$view_code'\n";
		
		my $pref = AppCore::Web::Common::getcookie('mobile.sitepref');
		$view_code = 'mobile' if $pref eq 'mobile';
		
# 		if($view_code eq 'home')
# 		{
# 			$tmpl = $self->load_template('frontpage.tmpl');
# 		}
# 		elsif($view_code eq 'admin')
# 		{
# 			$tmpl = $self->load_template('admin.tmpl');
# 		}
# 		elsif($view_code eq 'mobile')
# 		{
# 			$tmpl = $self->load_template('mobile.tmpl');
# 		}
# 		# Don't test for 'sub' now because we just want all unsupported view codees to fall thru to subpage
# 		#elsif($view_code eq 'sub')
# 		else
		{
			#$tmpl = $self->load_template('subpage.tmpl');
			$tmpl = $self->load_template('frontpage.tmpl');
		}
		
		## Add other supported view codes
			
		$self->auto_apply_params($tmpl,$page_obj);
		
		$r->output($tmpl); #->output);
	};
	
};

1;