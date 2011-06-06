use strict;


package Boards::TextFilter::AutoLink;
	{ 
		use base 'Boards::TextFilter';
		__PACKAGE__->register("Auto-Link","Adds hyperlinks to text.");
		
		# This actual filter can serve as a simple example:
		# It just accepts a scalar ref and runs a regexp over the text (note the double $$ to deref)
		sub filter_text
		{
			my $self = shift;
			my $textref = shift;
			#print STDERR "AutoLink: Before: ".$$textref."\n";
			
			$$textref =~ s/http:\/\/\%20http\/\//http:\/\//g; # cleanup an invalid link I've seen once or twice ...
			
			# Old regex:
			#$$textref =~ s/(?<!(\ssrc|href)=['"])((?:http:\/\/www\.|www\.|(?:http|ftp|telnet|file|nfs):\/\/)[^\s]+)/<a href="$2">$2<\/a>/gi;
			
			# New regex:
			$$textref =~ s/([^'"\/<>:]|^)((?:(?:http|ftp|telnet|file):\/\/|www\.)([^\s<>'"]+))/$1<a href="$2">$2<\/a>/gi;
			
			#print STDERR "AutoLink: After: ".$$textref."\n";
		};
		
	};
	
package Boards::TextFilter::ImageLink;
	{ 
		use base 'Boards::TextFilter';
		__PACKAGE__->register("Link Images","Add an image below the post if found in the text");
		
		sub filter_text
		{
			my $self = shift;
			my $textref = shift;
			return if $$textref =~ /<img/i; # Don't do our magic if the text already contains an <img> tag
			
			# Extract all URLs from text
			my @urls = $$textref =~ /((?:http|ftp|https):\/\/[\w\-_]+(?:\.[\w\-_]+)+(?:[\w\-\.,@?^=%&:\/~\+#]*[\w\-\@?^=%&\/~\+#])?)/g;
			
			# Get only images (add more extensions as desired...)
			@urls = grep { /\.(jpg|gif|png)/ } @urls; 
			
			my %hash = map { $_ => 1 } @urls; # Only use each url once 
			@urls = grep { $_ } keys %hash; # Filter out empty URLs
			 
			# Only add the <hr> if there really are images available
			if(@urls)
			{
				# Add links to the image
				$$textref .= "<hr size=1 class='post-attach-divider'>";
				$$textref .= join '', map qq{
					<a href='$_' class='image-link' title='Click to view image'>
					<img src="$_" border=0>
					<span class='overlay'></span>
					</a>
				}, @urls;
			}
		};
	};

package Boards::VideoProvider::YouTube;
	{
		use base 'Boards::VideoProvider';
		__PACKAGE__->register({
			name		=> "YouTube",						# Name isn't used currently
			provider_class	=> "video-youtube",					# provider_class is used in page to match provider to iframe template, and construct template and image ID's
			url_regex	=> qr/(http:\/\/www.youtube.com\/watch\?v=[a-zA-Z0-9\-]+)/,	# Used to find this provider's URL in content
			
			iframe_size	=> [375,312],						# The size of the iframe - used to animate the link block element size larger to accomidate the new iframe
												# The iframe template is used by jQuery's template plugin to generate the iframe html
			iframe_tmpl	=> '<iframe title="YouTube video player" width="375" height="312" '.
						'src="http://www.youtube.com/embed/${videoid}?autoplay=1" '.
						'frameborder="0" class="youtube-iframe" allowfullscreen></iframe>'
		});
		
		# Expected to return an array of (link URL, image URL, video ID) - videoId is set on the <a> tag in a custom 'videoid' attribute
		sub process_url 
		{
			my $self = shift;
			my $url = shift;
			my ($code) = $url =~ /v=([a-zA-Z0-9\-]+)/;
			#print STDERR "youtube url: $url, code: $code\n";
			return ($url, "http://img.youtube.com/vi/$code/1.jpg", $code);
		};
	};
	
package Boards::VideoProvider::Vimeo;
	{
		use base 'Boards::VideoProvider';
		__PACKAGE__->register({	
			name		=> "Vimeo",
			provider_class	=> "video-vimeo",
			url_regex	=> qr/vimeo\.com\/(\d+)/,
			
			iframe_size	=> [320,240],
			iframe_tmpl	=> '<iframe src="http://player.vimeo.com/video/${videoid}'.
						'?portrait=0&amp;autoplay=1" width="320" height="240" frameborder="0"></iframe>',
						
			# This 'extra_js' is just inserted into the page exactly as-is (in a <script></script> tag of course)
			# Since Vimeo doesn't provide a consistent thumbnail URL like youtube, we must use javascript to request
			# the video metadata from Vimeo then extract the thumbnail URL from that and update the image dynamically.
			extra_js	=> q|
				// Get all Viemo video links and create a script request to Vimeo for the thumbnail URL
				$('a.video-vimeo').each(function() {
					var th = $(this),
					id = th.attr("videoid"),
					url = "http://vimeo.com/api/v2/video/" + id + ".json?callback=showThumb",
					id_img = "#video-vimeo-" + id;
					$(id_img).before('<scr'+'ipt type="text/javascript" src="'+ url +'"></scr'+'ipt>');
					//console.debug("found Vimeo video ID "+id);
				});
				// This handles the thumbnail callback from vimeo - grabs the url, sets it on the image and resizes the image accordingly
				function showThumb(data)
				{
					$("#video-vimeo-" + data[0].id)
						.attr('src',data[0].thumbnail_small)
						.animate({width:120,height:90},1);
						// 120x90 is the size of the youtube thumb - its set in CSS, so we just match it toi look consistent
				}
			|
		});
		
		sub process_url	
		{
			my $self = shift;
			my $code = shift;
			my $url = "http://www.vimeo.com/$code";
			return ($url, $AppCore::Config::WWW_ROOT."/images/blank.gif", $code);
			# Return a 'blank' image for the thumbnail here because we use javascript in-page to find the thumbnail 
			# URL after the page is loaded. If one felt like it, you could instead call out to vimeo in this sub 
			# and cache the resulting thumbnail URL for later. But for now, this implementation works fine with in-page
			# javascript.
		}
			
	};


package Boards;
{
	use AppCore::Web::Common;
	use AppCore::Common;
	use AppCore::EmailQueue;
	
	# Inherit both a Web Module and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	# For proper redirection to the right page
	use Content::Page;
	
	# For making MD5's of emails
	use Digest::MD5 qw/md5_hex/;
	
	# For outputting JSON for new posts
	use JSON qw/encode_json decode_json/;
	
	# Contains all the data packages we need, such as Boards::Post, etc
	use Boards::Data;
	
	# The 'banned words' library which parses the Dan's Guardian words list
	use Boards::BanWords;
	
	our $SUBJECT_LENGTH    = 50;
	our $MAX_FOLDER_LENGTH = 225;
	our $SPAM_OVERRIDE     = 0;
	our $SHORT_TEXT_LENGTH = 60;
	our $LAST_POST_SUBJ_LENGTH = $SUBJECT_LENGTH;
	our $APPROX_TIME_REFERESH  = 15; # seconds
	our $INDENT_MULTIPLIER = 4; # I feel so dirty putting this in the code instead of a template - but I feel even dirtier putting an expression in CSS, so it's here...
	
	# Setup our admin package
	use Admin::ModuleAdminEntry;
	Admin::ModuleAdminEntry->register(__PACKAGE__, 'Boards', 'boards', 'List all boards on this site and manage boards settings.');
	
	# Register our pagetype
	our $PAGE_TYPEID = __PACKAGE__->register_controller('Board Page','Bulletin Board Front Page',1,0,  # 1 = uses page path,  0 = doesnt use content
		[
			{ field => 'title',		type => 'string',	description => 'The title of the bulletin board' },
			{ field => 'tagline',		type => 'string',	description => 'A short description of the board' },
			{ field => 'description', 	type => 'text',		description => 'A long description of the board to appear on the board page itself' }, 
		]
	);
	
	# Register user preferences
	our $PREF_EMAIL_ALL      = AppCore::User::PrefOption->register(__PACKAGE__, 'Notification Preferences', 'Send me an email for all new posts');  # defaults to bool for datatype and true for default value
	our $PREF_EMAIL_COMMENTS = AppCore::User::PrefOption->register(__PACKAGE__, 'Notification Preferences', 'Send me an email when someone comments on my posts');
	
	# Setup the Web Module 
	sub DISPATCH_METHOD { 'main_page'}
	
	# Directly callable methods
	__PACKAGE__->WebMethods(qw{});

	# Hook for our database objects
	sub apply_mysql_schema
	{
		Boards::DbSetup->apply_mysql_schema;
	}
	
	# Creation for our web module
	sub new
	{
		my $self = shift;
		
		my $self = bless {}, $self;
		
		$self->config(); # Init config
		
		return $self;
	};
	
	# Accessor for config hash
	sub config
	{
		my $self = shift;
		if(!$self->{config})
		{
			$self->{config} = {};
			
			# Setup default board config - can be updated by subclasses
			$self->apply_config(
			{
				short_noun	=> 'Boards',
				long_noun	=> 'Bulletin Boards',
				
				post_reply_tmpl	=> 'post_reply.tmpl',
				new_post_tmpl	=> 'new_post.tmpl',
				post_tmpl	=> 'post.tmpl',
				list_tmpl	=> 'list.tmpl',
				edit_forum_tmpl	=> 'edit_forum.tmpl',
				main_tmpl	=> 'main.tmpl',
				
				admin_acl	=> ['Admin-WebBoards'],
			});
		}
		
		return $self->{config} || {};
	};
	
	# This only overrites the config keys present in the incoming config, not all config data.
	# Use in a subclass to apply a hashref of config keys to the existing config
	sub apply_config
	{
		my $self = shift;
		my $config = shift;
		my $config_ref = $self->{config};
		$config_ref->{$_} = $config->{$_} foreach keys %$config;
		
		#print STDERR Dumper $self->{config};
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
		my $themeid   = $page_obj ? $page_obj->themeid   : undef;
		my $view_code = $page_obj ? $page_obj->view_code : undef;
		
		if($themeid && $themeid->id)
		{
			# Change current theme if the page requests it
			$self->theme($themeid->controller);
		}
		
		#print STDERR "process_page: view_code is '$view_code', type: $type_dbobj\n";
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
		
		#print STDERR "process_page: view_code is '$view_code', type: $type_dbobj\n";
		
		# If the last part of the URL is a valid bulletin board (e.g. this page)
		# then move that part from the page path to path info
		my $lp = $req->last_path;
		my $other = Boards::Board->by_field(folder_name => $lp);
		
# 		use Data::Dumper;
# 		print STDERR __PACKAGE__."::process_page(): lp: '$lp', other:'$other', dump:".Dumper($req)."\n";
		
		if($other)
		{
			my $pp = $req->pop_page_path;  # pop from pagepath ...
			$req->unshift_path($pp); # and unshift into path info
#			print STDERR __PACKAGE__."::process_page(): poped and unshiffted, new page_path:".$req->page_path.", dump:".Dumper($req)."\n";
		}
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = $AppCore::Config::DISPATCHER_URL_PREFIX . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		#return $self->dispatch($req, $r);
		return $self->main_page($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
	## TODO ##
	
	# Main areas:
	# main_page - list of all boards
	# board_page - page listing posts (search/print/paging,etc)
	# post_page - viewing one post
	# user_page - user's home page
	
	# Function: main_page()
	# List all boards that are not hidden/private/user created (basically 'System' boards)
	sub main_page
	{
		#my ($skin,$r,$page,$req,$path) = @_;
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		
		#$r->header('X-Page-Comments-Disabled' => 1);
		
		# TODO #
		# If this is a pagetype request, check the pageid of the board and make sure we are routing thru that URL/controller 
		
		# If used as a page type, the current path would be whatever the root of the page is
		# Next path element would be the board requested, then the post
		# So if a page type, then URL could be:
		# /physh/discussions/leaders/2011_hayride_ideas
		# Where:
		# /physh/discussions is the page object in Content::Page with our pagetype
		# /leaders is the forum name
		# /2011_hayride_ideas is the post name
		
		# If not a pagetype, we will be reached by the module url /boards/$forum/$post
		
		my $sub_page = $req->next_path;
		
		my $bin = $self->binpath;
		
		if($sub_page eq 'new')
		{
			AppCore::AuthUtil->require_auth($self->config->{admin_acl});
			my $tmpl = $self->get_template($self->config->{edit_forum_tmpl} || 'edit_forum.tmpl');
			$tmpl->param(post_url => "$bin/post");
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			
			
			my $group = Boards::Group->retrieve($req->{groupid});
			$r->error("Invalid GroupID","Invalid GroupID") if !$group;
			$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			
			$self->board_settings_new_hook($tmpl) if $self->can('board_settings_new_hook');
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'edit')
		{
			AppCore::AuthUtil->require_auth($self->config->{admin_acl});
			my $tmpl = $self->get_template($self->config->{edit_forum_tmpl} || 'edit_forum.tmpl');
			$tmpl->param(post_url => "$bin/post");
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			#my $config = $self->config;
			#print STDERR Dumper $config;
			
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			
			my $board = Boards::Board->retrieve($req->{boardid});
			$r->error("Invalid BoardID","Invalid BoardID") if !$board;
			my $group = $board->groupid;
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			
			$self->board_settings_edit_hook($board,$tmpl) if $self->can('board_settings_edit_hook');
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'post')
		{
			AppCore::AuthUtil->require_auth($self->config->{admin_acl});
			my $board;
			if($req->{boardid})
			{
				$board = Boards::Board->retrieve($req->{boardid});
			}
			else
			{
				$board = Boards::Board->create({groupid => $req->{groupid},
					#section_name=>$section_name ## TODO Replace this with the pageid!
				});
			}
			
			$self->board_settings_save_hook($board,$req) if $self->can('board_settings_save_hook');
			
			foreach my $key (qw/folder_name title tagline sort_key/)
			{
				$board->set($key, $req->{$key});
			}
			
			
			$board->update;
			
			$r->redirect($bin); 
		}
		elsif($sub_page eq 'feed.xml' || $sub_page eq 'rss')
		{
# 			my $tmpl = $self->rss_feed('',$req->{include_comments});
# 		
# 			$r->content_type('application/rss+xml ');
# 			$r->body($tmpl->output);
			return;
		}
		elsif($sub_page)
		{
			return $self->board_page($req,$r);
		}
		else
		{
			my $tmpl = $self->get_template($self->config->{main_tmpl} || 'main.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});;
			$tmpl->param(can_admin=>$can_admin);
		
			my @groups = Boards::Group->search(hidden=>0);
			@groups = sort {$a->sort_key cmp $b->sort_key} @groups;
			
			my $appcore = $AppCore::Config::WWW_ROOT;
			
			foreach my $g (@groups)
			{
				$g->{$_} = $g->get($_) foreach $g->columns;
				$g->{bin} = $bin;
				$g->{appcore} = $appcore;
				
				my @boards = Boards::Board->search(groupid=>$g);
				@boards = sort {$a->sort_key cmp $b->sort_key} @boards;
				foreach my $b (@boards)
				{
					$b->{$_} = $b->get($_) foreach $b->columns;
					$b->{bin} = $bin;
					$b->{appcore} = $appcore;
					$b->{can_admin} = $can_admin;
					$b->{board_url} = "$bin/$b->{folder_name}";
					
					my $lc = $b->last_commentid;
					if($lc && $lc->id && !$lc->deleted)
					{
						$b->{'post_'.$_} = $lc->get($_) foreach $lc->columns;
						$b->{post_url} = "$bin/$b->{folder_name}/".$lc->top_commentid->folder_name."#c$lc" if $lc->top_commentid;
					}
				}
				
				$g->{can_admin} = $can_admin;
				$g->{boards} = \@boards;
			}
			
			$tmpl->param(groups => \@groups);
			
# 			$r->html_header('link' => 
# 			{
# 				rel	=> 'alternate',
# 				title	=> 'Pleasant Hill Church RSS',
# 				href 	=> 'http://www.mypleasanthillchurch.org'.$bin.'/boards/rss',
# 				type	=> 'application/rss+xml'
# 			});
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
	}
	
	sub macro_board_nav
	{
		my $self = shift;
		#print STDERR "path_info: $ENV{PATH_INFO}\n";
		my @path = split/\//, $ENV{PATH_INFO};
		
		shift @path if !$path[0];
		my $first 	= shift @path;
		my $forum 	= shift @path;
		my $post 	= shift @path;
		my $action 	= shift @path;
		#print STDERR "forum=$forum, post=$post, action=$action\n";
		
		
		my $noun = $self->config->{short_noun} || 'Boards';
		
		if($forum)
		{
			my @list;
			my $bin = AppCore::Common->context->http_bin;
			
			my $board = Boards::Board->by_field(folder_name => $forum);
			push @list, "<a href='$bin/$first' class='first'>$noun</a> &raquo; ";
			if($forum ne 'edit' && $forum ne 'new')
			{
				push @list, "<a href='$bin/$first/$forum' class='first ".(!$post || $post eq 'new' ? 'current' : '')."'>".$board->title."</a>" if $board;
				
				if($post && $post ne 'new')
				{
					my $post_ref = Boards::Post->by_field(folder_name => $post);
					if($post_ref)
					{
						$list[$#list].=' &raquo; ';
						push @list, "<a href='$bin/$first/$forum/$post' class='first current'>".$post_ref->subject."</a>";
					}
				}
			}
			
			
			#print STDERR Dumper \@list;
			return '<div class="sub_nav board_nav">You are here: ' . join('',@list) . '</div>';
		}
		else
		{
			#print STDERR "no g children\n";
			return '';
		}
	}
	
	our %PostDataCache;
	our %BoardDataCache;
	our @TextFilters;
	our @VideoProviders;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
		%BoardDataCache = ();
		%PostDataCache = ();
		@TextFilters = ();
		@VideoProviders = ();
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	
	sub get_controller
	{
		my $self = shift;
		my $board = shift;
		
		my $controller = $self;
		
		#die $board->folder_name;
		if($board->forum_controller)
		{
			#eval 'use '.$board->forum_controller;
			#die $@ if $@ && $@ !~ /Can't locate/;
			
			$controller = AppCore::Web::Module->bootstrap($board->forum_controller);
			$controller->binpath($self->binpath);
		}
		
		return $controller;
	}
	
	
	sub user_page
	{
		my $self = shift;
		#my ($section_name,$folder_name,$skin,$r,$page,$req,$path) = @_;
		my $req = shift;
		my $r = shift;
		my $user = shift || undef;
		
		if(!$user)
		{
			my $username = $req->next_path;
			$user = AppCore::User->by_field(user => $username);
			
			if(!$user)
			{
				return $r->error("No Such User", "Sorry, the user you requested does not exist");	
			}
		}
		
		if(!$user)
		{
			return $r->error("No User Given","Sorry, no user given");
		}
		
		
		my $board = Boards::Board->by_field(board_userid => $user);
		 
		if(!$board)
		{
			my $group = Boards::Group->find_or_create({ title=> 'User Walls' }); 
			$board = Boards::Board->create({
				groupid 	=> $group->id, 
				board_userid	=> $user,
				managerid	=> $user,
				folder_name	=> $user->user,
				title		=> $user->display.'\'s Wall',
			});
			
			print STDERR "Boards::user_page(): Created new user wall: boardid $board for user '". $user->display. "'\n";
		}
			
		return $self->board_page($req,$r,$board);
		
	}
	
	
	sub board_page
	{
		my $self = shift;
		#my ($section_name,$folder_name,$skin,$r,$page,$req,$path) = @_;
		my $req = shift;
		my $r = shift;
		my $board = shift || undef;
		
		my $folder_name = $req->shift_path;
		
		# Make sure we are being accessed thru a Content::Page object if one exists with "our name on it", so to speak
		if(!$req->{page_obj})
		{
			my $sth = ($self->{_sth_pagecheck} ||= Content::Page->db_Main->prepare('select pageid from `'.Content::Page->table.'` where url like ? and typeid=?'));
			$sth->execute("%/${folder_name}",$PAGE_TYPEID);
			if($sth->rows)
			{
				my $page = Content::Page->retrieve($sth->fetchrow);
				my $cur_url = $req->page_path."/$folder_name";
				#print STDERR get_full_url().": board_page: Matched folder $folder_name to pageid $page, page url:".$page->url.", current path: $cur_url\n";
				if($page->url ne $cur_url)
				{
					my $new_url = $page->url.($req->path?"/".join('/',$req->path_info):"").($ENV{QUERY_STRING} ? '?'.$ENV{QUERY_STRING} : '');
					print STDERR get_full_url().": board_page: Redirecting to $new_url\n";
					return $r->redirect($new_url);
				}
			}
		}
		
		
		$req->push_page_path($folder_name);
		
		$board = Boards::Board->by_field(folder_name => $folder_name) if !$board;
		if(!$board)
		{
			return $r->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		my $controller = $self->get_controller($board);
		
		my $sub_page = $req->next_path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = $self->binpath;
		
		if($sub_page eq 'post')
		{
			my $post = $controller->create_new_thread($board,$req);
			
			$controller->send_notifications('new_post',$post);
			#$r->redirect(AppCore::Common->context->http_bin."/$section_name/$folder_name#c$post");
			
			if($req->output_fmt eq 'json')
			{
				my $b = $controller->load_post_for_list($post,$board->folder_name);
				
				#use Data::Dumper;
				#print STDERR "Created new postid $post, outputting to JSON, values: ".Dumper($b);
				
				my $json = encode_json($b);
				return $r->output_data("application/json", $json);
			}
			
			return $r->redirect("$bin/$folder_name");
		}
		elsif($sub_page eq 'new')
		{
			my $tmpl = $self->get_template($controller->config->{new_post_tmpl} || 'new_post.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $controller->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $controller->config->{long_noun}  || 'Bulletin Boards');
			$tmpl->param(post_url => "$bin/$folder_name/post");
			
			#die $controller;
			$controller->new_post_hook($tmpl,$board);
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('New Post',"$bin/$folder_name/new",0);
			$view->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'print_list')
		{
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
			
			my $tmpl = $self->get_template($controller->config->{print_list_tmpl} || 'print_list.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $controller->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $controller->config->{long_noun}  || 'Bulletin Boards');
			
			my $tmpl_incs = $controller->config->{tmpl_incs} || {};
			foreach my $key (keys %$tmpl_incs)
			{
				$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
			}
			
			my @id_list = split /,/, $req->{id_list};
			
			my @posts = map { Boards::Post->retrieve($_) } @id_list;
			
			#sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			my @output_list = map { $controller->load_post($_,$req,1) } @posts; # 1 = dont count this load as a 'view'
			foreach my $b (@output_list)
			{
				$b->{bin}         = $bin;
				$b->{folder_name} = $folder_name;
				$b->{can_admin}   = $can_admin;
			}
			
			$tmpl->param(post_list => \@output_list);
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'delete_list')
		{
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
			
			die "Access denied - you're not an admin" if !$can_admin;
			
			my @id_list = split /,/, $req->{id_list};
			
			my @posts = map { Boards::Post->retrieve($_) } @id_list;
			
			foreach my $post (@posts)
			{
				$post->deleted(1);
				$post->update;
			}
			
			return $r->redirect("$bin/$folder_name");
			
		}
		elsif($sub_page)
		{
			return $self->post_page($req,$r,$controller);
		}
		else
		{
			my $dbh = Boards::Post->db_Main;
			
			my $user = AppCore::Common->context->user;
			my $can_admin = $user && $user->check_acl($controller->config->{admin_acl}) ? 1 :0;
			my $board_folder_name = $board->folder_name;
			
			my $user_wall_clause = 0; # Since this var is used in an "or" statement, the 0 will null it out unless we put something there
			
			# This board is specific to a user if board_userid is set
			my $board_userid = 0;
			if($board->board_userid && $board->board_userid->id)
			{
				my $user = $board->board_userid;
				my $userid = $board_userid = $user->id.''; # cast to string for tainting...
				$userid =~ s/[^\d]//g; # taint just to be safe...
				$userid += 0;  # force cast to int...
				$user_wall_clause = 'posted_by='. $userid;
			}
			
			
			# Check to see if this is an ajax poll request for new posts
			if($req->{first_ts})
			{
				my $postid = $req->{postid};
				my $from_str = $req->{from};
				#print STDERR "POLL: Postid: $postid, Timestamp: $req->{first_ts}\n" if $postid;
				my $sth = $dbh->prepare_cached(
					'select b.*, u.photo as user_photo, u.user as username '.
					'from board_posts b left join users u on (b.posted_by=u.userid) '.
					"where (boardid=? or $user_wall_clause) and timestamp>? ".
					($postid? 'and top_commentid=?':' ').
					($from_str? 'and poster_name=?':' ').
					'and deleted=0 order by timestamp');
				
				my @args = ($board->id, $req->{first_ts});
				push @args, $postid if $postid;
				push @args, $from_str if $from_str;
				
				$sth->execute(@args);
				my @results;
				my $ts;
				while(my $b = $sth->fetchrow_hashref)
				{
					my $x = $controller->load_post_for_list($b,$board_folder_name,$can_admin);
					$ts = $x->{timestamp};
					push @results, $x;
				}
				
				my $output = 
				{
					list	=> \@results,
					count	=> scalar @results,
					last_ts	=> $ts,
				};
				
				my $json = encode_json($output);
				return $r->output_data("application/json", $json) if $req->output_fmt eq 'json';
				return $r->output_data("text/plain", $json);
			}
			
			# Get the current paging location
			my $idx = $req->idx || 0;
			my $len = $req->len || $AppCore::Config::BOARDS_POST_PAGE_LENGTH;
			$len = $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH if $len > $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH;
			
			# Find the total number of posts in this board
			my $find_max_index_sth = $dbh->prepare_cached("select count(b.postid) as count from board_posts b where (boardid=? or $user_wall_clause) and top_commentid=0 and deleted=0");
			$find_max_index_sth->execute($board->id);
			my $max_idx = $find_max_index_sth->rows ? $find_max_index_sth->fetchrow : 0;
			
			$find_max_index_sth->finish; # prevent warnings from DBI for the prepare_cached() stmt...
			
			my $next_idx = $idx + $len; 
			$next_idx = $next_idx >= $max_idx ? 0 : $next_idx; # If next idx past end, set to 0 to indicate to tmpl that there are no more posts ...
			$next_idx = 0 if !$len; # If paging disabled, there is no next idx...
			
			# Create a cache key for this set of posts based on the board id, user (if logged in), and the current page (idx/len) 
			my $cache_key = $user ? $board->id . $user->id : $board->id;
			$cache_key .= $idx if $idx;
			$cache_key .= $len if $len;
			
			# Try to load data from in-memory cache - if cache miss, well, rebuild!
			my $data = $BoardDataCache{$cache_key};
			if(!$data)
			{
				my $sth;
				
				if(!$len)
				{
					# If paging disabled, just use a single query to load everything
					$sth = $dbh->prepare_cached(qq{
						select p.*,b.folder_name as original_board_folder_name,b.title as board_title, u.photo as user_photo, u.user as username from board_posts p left join users u on (p.posted_by=u.userid), boards b where p.boardid=b.boardid and (p.boardid=? or $user_wall_clause) and deleted=0 order by timestamp desc, postid desc 
					});
				}
				else
				{
					# Paging not disabled, so first we get a list of postids (e.g. not the comments) to load - since the doing a limit (?,?) for comments would miss some ikder comments
					# that should be included because the post is included
					my $find_posts_sth = $dbh->prepare_cached("select b.postid from board_posts b where (boardid=? or $user_wall_clause) and top_commentid=0 and deleted=0 order by timestamp desc, postid desc limit ?,?");
					$find_posts_sth->execute($board->id, $idx, $len);
					my @posts;
					push @posts, $_ while $_ = $find_posts_sth->fetchrow;
					
					# Keep user from getting a "dirty" error by giving a simple error
					if(!@posts)
					{
						#return $r->error("No posts at index ".($idx+0));
						@posts = (0); # Allow the page to be empty :-)
					}
					
					my $list = join ',',  @posts;
					
					# Now do the actual query that loads both posts and comments in one gos
					$sth = $dbh->prepare_cached('select p.*,b.folder_name as original_board_folder_name,b.title as board_title, u.photo as user_photo, u.user as username from board_posts p left join users u on (p.posted_by=u.userid), boards b '.
						"where (((p.boardid=? or $user_wall_clause) and postid in (".$list.")) or top_commentid in (".$list.")) and deleted=0 and p.boardid=b.boardid ".
						'order by timestamp, postid desc');
				}
				
				$sth->execute($board->id);
				
				# First, prepare all the post results (posts and comments) at the same time
				# Create a crossref of posts to data objects for the next block which puts the comments with the parents
				my @tmp_list;
				my %crossref;
				my $first_ts = undef;
				while(my $b = $sth->fetchrow_hashref)
				{
					$first_ts = $b->{timestamp};# if !$first_ts;
					$b->{reply_count} = 0;
					$b->{board_userid} = $board_userid; 
					#die Dumper $b;
					push @tmp_list, $controller->load_post_for_list($b,$board_folder_name,$can_admin);
				}
				
				my $threaded = $controller->thread_post_list(\@tmp_list);
				my @list = @$threaded;
				# Put newest at top of list
				# (We load oldest->newest so that we can process comments correctly, but reverse so newest top post is at the top, but comments still will show old->new)
				@list = reverse @list;
				
				$data = 
				{
					list 		=> \@list,
					timestamp	=> time,
					first_timestamp	=> $first_ts, # Used for in-page polling dyanmic new content inlining
				};
				$BoardDataCache{$cache_key} = $data;
				#print STDERR "[-] BoardDataCache Cache Miss for board $board (key: $cache_key)\n"; 
				
				#die Dumper \@list;
			}
			else
			{
				#print STDERR "[+] BoardDataCache Cache Hit for board $board\n";
				
				# Go thru and update approx_time_ago fields for posts and comments
				if((time - $data->{timestamp}) > $APPROX_TIME_REFERESH)
				{
					# This loop takes approx 20-30ms on a few of my tests
					# Therefore, we only run it if the data is more than $APPROX_TIME_REFERESH seconds old
					
					foreach my $ref (@{$data->{list} || []})
					{
						$ref->{approx_time_ago} = approx_time_ago($ref->{timestamp});
						foreach my $reply (@{$ref->{replies} || []})
						{
							$reply->{approx_time_ago} = approx_time_ago($reply->{timestamp});
						}
					}
					
					$data->{timestamp} = time;
				}
			}
			
			my $board_ref = {};
			$board_ref->{$_} = $board->get($_)."" foreach $board->columns;
			
			my $output = 
			{
				board	=> $board_ref,
				posts	=> $data->{list},
				idx	=> $idx,
				idx1	=> $idx + 1,
				len	=> $max_idx < $len ? $max_idx : $len,
				idx2	=> $idx + $len > $max_idx ? $max_idx : $idx + $len,
				next_idx=> $next_idx >= $max_idx ? 0 : $next_idx,
				#first_id=> @{$data->{list}} ? $data->{list}->[0]->{postid} : 0,
				first_ts=> $data->{first_timestamp}, # Used for in-page polling dyanmic new content inlining
				max_idx => $max_idx,
				can_admin=> $can_admin,
			};
			
			$controller->forum_page_hook($output,$board);
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($output);
				return $r->output_data("application/json", $json);
				#return $r->output_data("text/plain", $json);
			}
			
			my $tmpl = $self->get_template($controller->config->{list_tmpl} || 'list.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param(user_email_md5 => md5_hex($user->email)) if $user && $user->id;
			$tmpl->param(boards_indent_multiplier => $INDENT_MULTIPLIER);
			
			my $tmpl_incs = $controller->config->{tmpl_incs} || {};
			#use Data::Dumper;
			#die Dumper $tmpl_incs;
			foreach my $key (keys %$tmpl_incs)
			{
				$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
			}
			
			# Since a theme has the option to inline a new post form in the post template,
			# provide the controller a method to hook into the template variables from here as well
			$controller->new_post_hook($tmpl,$board);
			
			$tmpl->param($_ => $output->{$_}) foreach keys %$output;
			
			$controller->apply_video_providers($tmpl);
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push($board->title,"$bin/$folder_name",0);
			$view->output($tmpl);
			return $r;
		}
	}
	
	sub apply_video_providers
	{
		my $self = shift;
		
		my $tmpl = shift;
		
		my @provider_copy = ();
			
		$self->load_video_providers;
		my @provider_configs;
		# @VideoProviders is already loaded by now, even if cache cleared it...
		foreach my $ref (@VideoProviders)
		{
			my $config = $ref->controller->config;
			push @provider_configs, $config;
			my %copy;
			$copy{$_} = $config->{$_} foreach qw/provider_class iframe_size extra_js/;
			push @provider_copy, \%copy;
		}
		$tmpl->param(video_provider_list_json => encode_json(\@provider_copy));
		$tmpl->param(video_provider_list => \@provider_configs);
	}
	
	sub load_post_for_list
	{
		my $self = shift;
		my $post = shift;
		my $board_folder_name = shift;
		my $can_admin = shift;
		my $dont_incl_comments = shift || 0;
		
		if(!defined $can_admin)
		{
			$can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		}
		
		
		my $short_len             = $AppCore::Config::BOARDS_SHORT_TEXT_LENGTH     || $SHORT_TEXT_LENGTH;
		my $last_post_subject_len = $AppCore::Config::BOARDS_LAST_POST_SUBJ_LENGTH || $LAST_POST_SUBJ_LENGTH;
		
		my $ref_name = ref $post;
		#print STDERR "Refname of post is '$ref_name', value '$post'\n";
		if($ref_name eq 'Boards::Post')
		{
			my $hash = {};
			$hash->{$_} = $post->{$_}."" foreach $post->columns;
			my $user = $post->posted_by;
			if($user && $user->id)
			{
				$hash->{username} = $user->user;
				$hash->{user_photo} = $user->photo;
			}
			
			$post = $hash;
		}
		
		#my $board_folder_name = $board->{folder_name};
		my $folder_name = $post->{folder_name};
		#my $user = $post->{posted_by};
		my $bin = $self->binpath;
		
		
		#my $b = {};
		
		my $b = $post;
		# Force stringification...
		## NOTE Assuming SQL Query already stringified everything. Assuming NOT from CDBI!!
# 		my @cols = $post->columns;
# 		$b->{$_} = $post->get($_). "" foreach @cols; #$post->columns;
		$b->{bin}         = $bin;
		$b->{appcore}     = $AppCore::Config::WWW_ROOT;
		$b->{board_folder_name} = $board_folder_name;
		$b->{can_admin}   = $can_admin;
		
		# NOTE: We set this here to PREVENT an error in the jQuery tmpl plugin when creating
		# posts inline via a json response from the server. The jQuery tmpl craps out and throws
		# an error when a variable is used in the template that is not defined in the parameters
		# given to the template function. So we MUST define EVERY variable used in the template
		# even if its not relevant to the current context - such as 'single_post_page'. But
		# 'single_post_page' IS used when viewing a single post - other than that, the template
		# should just default to undefined. HTML::Template handles it fine, but jQuery tmpl doesnt.
		# Grrrr.
		$b->{single_post_page} = 0;
		$b->{indent_is_odd}    = 0;
		$b->{board_userid}	= 0;
		$b->{original_board_folder_name} = '';
		
		
		my $cur_user = AppCore::Common->context->user;
		$b->{can_edit} = ($can_admin || ($cur_user && $cur_user->id == $b->{posted_by}) ? 1:0);
		
		$b->{ticker_class_title} = guess_title($b->{ticker_class}) if $b->{ticker_class};
		
		## NOTE Assuming SQL query already provided all user columns as user_*
# 		if($user && $user->id)
# 		{
# 			@cols = $user->columns;
# 			$b->{'user_'.$_} = $user->get($_) foreach @cols; #$user->columns;
# 		}
	
		#timemark();
		#$b->{text} = AppCore::Web::Common->clean_html($b->{comment})
		
		my $short = AppCore::Web::Common->html2text($b->{text});
		
		$b->{short_text}  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
		$b->{short_text_has_more} = length($short) > $short_len;
		
		my $clean_html = AppCore::Web::Common->text2html($b->{short_text});
		
		#$b->{short_text_html} =~ s/([^'"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/$1<a href="$1">$2<\/a>/gi;
		
		# Moved to the TEXT_FILTERS list to use as an example
		#$clean_html = $self->create_inline_links($clean_html);
		
		# Run all Boards::TextFilter on both the clean_html and the full text
		if(!@TextFilters)
		{
			# only load the 'enabled' filters (all are enabled by default)
			@TextFilters = Boards::TextFilter->search(is_enabled=>1);
		}
		
		my $text_tmp = AppCore::Web::Common->clean_html($b->{text});
		foreach my $filter (@TextFilters)
		{
			# Pass the text as a scalar ref
			$filter->controller->filter_text(\$clean_html);
			$filter->controller->filter_text(\$text_tmp);
		}
		
# 		open(LOG,">>/tmp/test.log");
# 		print LOG "postid $b->{postid}: $clean_html\n";
# 		close(LOG);
		
		#use Data::Dumper;
		#die Dumper \@TEXT_FILTERS;
		$b->{text}       = $self->create_video_links($text_tmp);
		$b->{clean_html} = $self->create_video_links($clean_html);
		
		# Trim whitespace off start/end of html
		$b->{clean_html} =~ s/(^\s|\s+$)//g;
		
		#use Data::Dumper;
		#die Dumper($b) if $b->{postid} == 10585;
		
		
		# just for jQuery's sake - the template converter in AppCore::Web::Result treats variables ending in _html special
		$b->{text_html} = $b->{text}; 
		#timemark("html processing");
		
		
		$b->{poster_email_md5} = md5_hex($b->{poster_email});
		$b->{approx_time_ago}  = approx_time_ago($b->{timestamp});
		$b->{pretty_timestamp} = pretty_timestamp($b->{timestamp});
		
		my $reply_to_url   = "$bin/$board_folder_name/$folder_name/reply_to";
		my $delete_base    = "$bin/$board_folder_name/$folder_name/delete";
		my $like_url       = "$bin/$board_folder_name/$folder_name/like";
		my $unlike_url     = "$bin/$board_folder_name/$folder_name/unlike";
		
		$b->{reply_to_url} = $reply_to_url;
		$b->{delete_base}  = $delete_base;
		$b->{like_url}     = $like_url;
		$b->{unlike_url}   = $unlike_url;
		
		Boards::Post::Like->like_data_for_post($b->{postid}, $b);
		
		#$b->{text} = PHC::VerseLookup->tag_verses($b->{text});
		
		return $b;
	}
	
	# Moved to the TEXT_FILTERS list to use as an example
# 	sub create_inline_links
# 	{
# 		my $self = shift;
# 		my $text = shift;
# 		$text =~ s/(?<!(\ssrc|href)=['"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/<a href="$2">$2<\/a>/gi;
# 		return $text;
# 	}

	sub load_video_providers
	{
		if(!@VideoProviders)
		{
			@VideoProviders = Boards::VideoProvider->search(is_enabled => 1);
		}
	}
	
	sub create_video_links
	{
		my $self = shift;
		my $text = shift;
		
		# Make sure it's loaded...
		$self->load_video_providers;
		
		foreach my $provider (@VideoProviders)
		{
			my $config = $provider->controller->config;
			my $rx = $config->{url_regex};
			my ($url) = $text =~ /$rx/;
			if($url)
			{
				my ($link_url, $thumb_url, $videoid) = $provider->controller->process_url($url);
				
				my $provider_class = $config->{provider_class};
				
				#my ($code) = $url =~ /v=(.+?)\b/;
				#$b->{short_text_html} .= '<hr size=1><iframe title="YouTube video player" width="320" height="240" src="http://www.youtube.com/embed/'.$code.'" frameborder="0" allowfullscreen></iframe>';;
				$text .= qq{
					<hr size=1 class='post-attach-divider'>
					<a href='$link_url' class='video-play-link $provider_class' videoid='$videoid'>
					<img src="$thumb_url" border=0 id='$provider_class-$videoid'>
					<span class='overlay'></span>
					</a>
				};
			}
		}
		
		return $text;
	}
	
	# This allows subclasses to hook into the list prep above without subclassing the entire list action
	sub forum_list_hook#($post)
	{}
	sub forum_page_hook#($output_hashref,$board)
	{}
	
	sub new_post_hook#($tmpl,$board)
	{}
	
	# Create a hash of values for use in a template or other output 
	sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
	{
		my $self = shift;
		
		my $post = shift;
		my $req  = shift;
		my $dont_count_view = shift || 0;
		my $more_local_ctx  = shift || undef;
		my $dont_incl_comments = shift || 0;
		
		my $first_ts = $post->timestamp;
		
		my $folder_name = $post->folder_name;
 		my $board_folder_name 
 		              = $post->boardid->folder_name;
		my $bin       = $self->binpath;
		
		unless($dont_count_view)
		{
			$post->num_views($post->num_views ? $post->num_views+1 : 0);
			$post->update;
		}
		
		# Create a cache key for this set of posts based on the board id, user (if logged in), and the current page (idx/len) 
		my $user = AppCore::Common->context->user;
		my $cache_key = $user ? $post->id . $user->id : $post->id;
		
		# Try to load data from in-memory cache - if cache miss, well, rebuild!
		my $post_ref = $PostDataCache{$cache_key};
		
		if(!$post_ref)
		{
			my $can_admin = $user && $user->check_acl($self->config->{admin_acl}) ? 1:0;
			
			# Do the actual query that loads all and comments in one gos
			my $sth = Boards::Post->db_Main->prepare_cached('select p.*,b.folder_name as original_board_folder_name, b.title as board_title, u.photo as user_photo, u.user as username from board_posts p left join users u on (p.posted_by=u.userid), boards b '.
				'where p.boardid=b.boardid and p.deleted=0 and '.
				'top_commentid=? '.
				'order by timestamp');
		
			$sth->execute($post->id);
			
			# First, prepare all the post results (posts and comments) at the same time
			my @tmp_list;
			while(my $b = $sth->fetchrow_hashref)
			{
				my $b = $self->load_post_for_list($b,$board_folder_name,$can_admin);
				$first_ts = $b->{timestamp};
				push @tmp_list, $b;
			}
			
			my $board = $post->boardid;
			$post_ref = $self->load_post_for_list($post,$board->folder_name,$can_admin);
			$post_ref->{'board_'.$_} = $board->get($_)."" foreach $board->columns;
			$post_ref->{'post_' .$_} = $post_ref->{$_}."" foreach $post->columns;
			$post_ref->{reply_count}  = 0;
			$post_ref->{first_ts} = $first_ts; # Used for in-page polling dyanmic new content inlining
	
			# Now we put all the comments with the parent posts
# 			my @list;
# 			my %indents;
# 			foreach my $data (@tmp_list)
# 			{
# 				# This is a comment, so we need to calculate an "indent" value 
# 				# for the template to use to indet the comment
# 				
# 				my $parent_comment = $data->{parent_commentid};
# 				my $indent = $indents{$parent_comment} || 0;
# 				my $id     = $data->{postid};
# 				
# 				$data->{indent}		= $indent;
# 				$data->{indent_css}	= $indent * 2;
# 				
# 				# Add the comment to the post
# 				push @{$post_ref->{replies}}, $data;
# 				
# 				$post_ref->{reply_count} ++;
# 				$indents{$id} = $indent + 1; 
# 			}
			$self->thread_post_list(\@tmp_list, $post_ref);
			
			$PostDataCache{$cache_key} = $post_ref;
		}
		
		return $post_ref;
	}
	
	sub thread_post_list
	{
		my $self        = shift;
		my $input       = shift || [];
		my $single_post = shift || undef;
		my $controller  = shift || $self;
		my @tmp_list = @{$input || []};
		
		# Used to clean up orphaned comments if the parent is deleted
		my $del_sth = Boards::Post->db_Main->prepare_cached('update board_posts set deleted=1 where postid=?',undef,1);
		
		my $tmpl_incs = $controller->config->{tmpl_incs} || {};
						
		my %crossref = map { $_->{postid} => $_ } @tmp_list;
					
		# Now we put all the comments with the parent posts
		my @list;
		my %indents;
		foreach my $data (@tmp_list)
		{
			# This is a parent post, just add it to the master list
			if(!$single_post && $data->{top_commentid} == 0)
			{
				foreach my $key (keys %$tmpl_incs)
				{
					$data->{'tmpl_inc_'.$key} = $tmpl_incs->{$key};
				}
				
				push @list, $data;
			}
			else
			{
				# This is a comment, so we need to calculate an "indent" value 
				# for the template to use to indet the comment
				
				my $parent_comment = $data->{parent_commentid};
				my $indent = $indents{$parent_comment} || 0;
				my $id     = $data->{postid};
				
				$data->{indent}		= $indent;
				$data->{indent_css}	= $indent * $INDENT_MULTIPLIER; # Arbitrary multiplier
				$data->{indent_is_odd}	= $indent % 2 == 0;
				
				# Lookup the top-most post for this comment
				# If its orphaned, we just delete the comment
				my $top_data = $single_post ? $single_post : $crossref{$data->{top_commentid}};
				if(!$top_data)
				{
					print STDERR "Odd: Orphaned child $data->{postid} - has top commentid $data->{top_commentid} but not in crossref - marking deleted.\n";
					$del_sth->execute($data->{postid});
				}
				else
				{
					# Add the comment to the post
					push @{$top_data->{replies}}, $data;
				}
	
				$top_data->{reply_count} ++;
				$indents{$id} = $indent + 1; 
			}	
		}
		
		# This funky foreach() block is required because of the way we structured the database query
		# Instead of multiple DB queries to get kids in the right order, we grab the entire list of kids
		# ordered by timestamp - so here we batch the kids by their parent then re-flatten the list out to a 1d list
		@list = ($single_post) if $single_post; 
		foreach my $post (@list)
		{
			my @list = @{$post->{replies} || []};
			next if !@list;

			# Make a map of comment id (postid) to the ref
			my %posts = map { $_->{postid} => $_ } @list;
			
			# Add each comment to a list of kids on its parent
			map { push @{$posts{$_->{parent_commentid}}->{tmp}}, $_ } @list;
			
			# Sort each list of kids by their timestamp
				# Dont need to sort by timestamp since they come sorted from the SQL query
			#map { $_->{tmp} = [ sort { $a->{timestamp} cmp $b->{timestamp} } @{$_->{tmp} || []} ] } @list;
			
			# Make a list of only top-level comments and sort by timestamp
				# Dont need to sort by timestamp since they come sorted from the SQL query
			my @tops = #sort { $a->{timestamp} cmp $b->{timestamp} } 
				grep { !$_->{parent_commentid} || $_->{parent_commentid} == $post->{postid} } @list;
			
			# Finally flatten out the list by building up a single level list of parents/comments in order
			my @final;
			sub pushit 
			{ 
				my $f = shift; 
				my $p = shift; 
				push @$f, $p;
				foreach my $k (@{$p->{tmp}})
				{
					pushit($f,$k);
				}
			}
			pushit(\@final, $_) foreach @tops;
			
			$post->{replies} = \@final;
		}
		
		return $single_post ? $single_post : \@list;
	}
	
	sub can_user_edit
	{
		my $self = shift;
		my $post = shift;
		local $_;
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		
		return $can_admin || (($_ = AppCore::Common->context->user) && $post->posted_by && $_->userid == $post->posted_by->id);
			
	}
	
	sub guess_subject
	{
		my $self = shift;
		my $text = shift;
		$text = AppCore::Web::Common->html2text($text);
		#$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
		my $idx = index($text,"\n");
		my $len = $idx > -1 && $idx < $SUBJECT_LENGTH ? $idx : $SUBJECT_LENGTH;
		return substr($text,0,$len) . ($idx < 0 && length($text) > $len ? '...' : '');
	}
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;
		my $user = shift;
		
		#print STDERR "create_new_thread: \$SPAM_OVERRIDE=$SPAM_OVERRIDE, args:".Dumper($req);
		if($self->is_spam($req->{comment}, $req->{bot_trap}))
		{
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		if(!$req->{subject})
		{
			$req->{subject} = $self->guess_subject($req->{comment});
		}
		
		my $fake_it = $self->to_folder_name($req->{subject});
		
		my $append_flag = 0;
		if(my $other = Boards::Post->by_field(folder_name => $fake_it))
		{
			$append_flag = 1;
		}
		
		$user = AppCore::Common->context->user if !$user;
		if($user && $user->id)
		{
			$req->{poster_name}  = $user->display	if !$req->{poster_name};
			$req->{poster_email} = $user->email	if !$req->{poster_email};
		}
		else
		{
			$req->{poster_name}  = 'Anonymous'          if !$req->{poster_name};
			$req->{poster_email} = 'nobody@example.com' if !$req->{poster_email};
		}
		
		# Try to guess if HTML is really just text
		if((!might_be_html($req->{comment}) || $req->{plain_text}) && !$req->{no_html_conversion})
		{
			$req->{comment} = text2html($req->{comment});
		}
		
		# Make sure it's loaded...
		$self->load_video_providers;
		
		my $post_class = undef;
		foreach my $provider (@VideoProviders)
		{
			my $config = $provider->controller->config;
			my $rx = $config->{url_regex};
			my ($url) = $req->{comment} =~ /$rx/;
			if($url)
			{
				$post_class = "video";
				last;
			}
		}
		
		if(!$post_class && 
		    $req->{comment} =~ /\.(jpg|gif|png)/)
		{
			$post_class = "image";
		}
		
		$post_class = "post" if !$post_class;
		
		my $photo = $req->{poster_photo};
		if(!$photo && $user && $user->id)
		{
			$photo = $user->photo;
		}
		
		my $post = Boards::Post->create({
			boardid			=> $board->id,
			poster_name		=> $req->{poster_name},
			poster_email		=> $req->{poster_email},
			poster_photo		=> $photo,
			posted_by		=> $user,
			timestamp		=> date(),
			subject			=> $req->{subject},
			text			=> $req->{comment},
			folder_name		=> $fake_it,
			post_class		=> $post_class,
			to_userid		=> $board->board_userid,
		});
		
		if($append_flag)
		{
			$fake_it = ($fake_it?$fake_it.'_':'').$post->id;
			$post->folder_name($fake_it);
			$post->update;
		}
		
		if($req->{tag})
		{
			$post->add_tag($req->{tag});
		}
		elsif($req->{tags})
		{
			s/(^\s+|\s+$)//g && $post->add_tag($_) foreach split /,/, $req->{tags};
		}
		
		return $post;
			
	}
	
	sub post_page
	{
		my $self  = shift;
		my $req   = shift;
		my $r     = shift;
		my $controller = shift || $self;
		
		my $folder_name = $req->shift_path;
		$req->push_page_path($folder_name);
		
		#my ($section_name,$folder_name,$board_folder_name,$skin,$r,$page,$req,$path) = @_;
		
		#print STDERR "\$section_name=$section_name,\$folder_name=$folder_name,\$board_folder_name=$board_folder_name\n";
		
		my $post = Boards::Post->by_field(folder_name => $folder_name);
		$post = Boards::Post->retrieve($folder_name) if !$post;
		if(!$post || $post->deleted)
		{
			return $r->error("No Such Post","Sorry, the post folder name you gave did not match any existing Bulletin Board posts. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		my $board             = $post->boardid;
		my $board_folder_name = $board->folder_name;
		
		my $sub_page = $req->shift_path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = $self->binpath;
		
		if($sub_page eq 'post')
		{
			my $comment     = $controller->create_new_comment($board,$post,$req);
			my $comment_url = "$bin/$board_folder_name/$folder_name#c" . $comment->id;
			
			$controller->send_notifications('new_comment',$comment);
			
			print STDERR __PACKAGE__."::post_page($post): Posted reply ID $comment to post ID $post\n";
			
			if($req->output_fmt eq 'json')
			{
				my $output = $controller->load_post_for_list($comment,$board->folder_name);
				
				my $json = encode_json($output);
				return $r->output_data("application/json", $json);
			}
			
			$r->redirect($comment_url);
		}
		elsif($sub_page eq 'reply' || $sub_page eq 'reply_to')
		{
			my $tmpl = $self->get_template($controller->config->{post_reply_tmpl} || 'post_reply.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			
			eval
			{
				my $reply_form_resultset = $controller->load_post_reply_form($post,$req->shift_path);
				$tmpl->param($_ => $reply_form_resultset->{$_}) foreach keys %$reply_form_resultset;
			};
			$r->error("Error Loading Form",$@) if $@;
			#$r->error("No Such Post","Sorry, the parent comment you gave appears to be invalid.");
			
			$tmpl->param(post_url => "$bin/$board_folder_name/$folder_name/post");
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Reply',"$bin/$folder_name/$sub_page",0);
			$view->output($tmpl);
			return $r;
				
		}
		elsif($sub_page eq 'delete')
		{
			if(!$controller->can_user_edit($post))
			{
				PHC::User::Auth->require_authentication($controller->config->{admin_acl});
			}
			
			my $type = $controller->post_delete($post,$req);
			
			if($type eq 'comment')
			{
				return $r->redirect("$bin/$board_folder_name/$folder_name");
			}
			else
			{
				return $r->redirect("$bin/$board_folder_name");
			}
		}
		elsif($sub_page eq 'like')
		{
			my $type = $controller->post_like($post,$req);
			
			if($req->output_fmt eq 'json')
			{
				return $r->output_data("application/json", "{like:1}");
			}
			
			if($type eq 'comment')
			{
				return $r->redirect("$bin/$board_folder_name/$folder_name");
			}
			else
			{
				return $r->redirect("$bin/$board_folder_name");
			}
		}
		elsif($sub_page eq 'unlike')
		{
			my $type = $controller->post_unlike($post,$req);
			
			if($req->output_fmt eq 'json')
			{
				return $r->output_data("application/json", "{unlike:1}");
			}
			
			if($type eq 'comment')
			{
				return $r->redirect("$bin/$board_folder_name/$folder_name");
			}
			else
			{
				return $r->redirect("$bin/$board_folder_name");
			}
		}
		elsif($sub_page eq 'edit')
		{
			if(!$controller->can_user_edit($post))
			{
				$r->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			my $tmpl = $self->get_template($controller->config->{new_post_tmpl} || 'new_post.tmpl');
			
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('folder_'.$board_folder_name => 1);
			
			my $edit_resultset = $controller->load_post_edit_form($post);
			$tmpl->param($_ => $edit_resultset->{$_}) foreach keys %$edit_resultset;
			
			$tmpl->param(post_url => "$bin/$board_folder_name/$folder_name/save");
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Edit Post',"$bin/$folder_name/edit",0);
			$view->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'save')
		{
			if(!$controller->can_user_edit($post))
			{
				$r->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			$controller->post_edit_save($post,$req);
			
# 			my $folder = $post->folder_name;
# 			
# 			my $abs_url = $self->module_url("$board_folder_name/$folder",1);
# 			
# 			my $email_body = $post->poster_name." edited post '".$post->subject."' in forum '".$board->title.qq{':
# 
#     }.AppCore::Web::Common->html2text($req->{comment}).qq{
# 
# Here's a link to that page: 
#     $abs_url
#     
# Cheers!};
# 			my @list = @AppCore::Config::ADMIN_EMAILS ? 
# 			           @AppCore::Config::ADMIN_EMAILS : 
# 			          ($AppCore::Config::WEBMASTER_EMAIL);
# 			AppCore::EmailQueue->send_email([@list],"[$AppCore::Config::WEBSITE_NAME] Post Edited: '".$post->subject."' in forum '".$board->title."'",$email_body);
		
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json({status=>'ok'});
				#return $r->output_data("application/json", $json);
				return $r->output_data("application/json", $json);
			}
			else
			{
				$r->redirect("$bin/$board_folder_name/".$post->folder_name);
			}
				
		}
		else
		{
			
			## TODO ## Handle this redirect in a more generic way - not sure exactly what/why this is here, but I know its needed....come back later and figure it out...20110429
# 			if($board_folder_name eq 'ask_pastor') #|| $board_folder_name eq 'pastors_blog')
# 			{
# 				my $prefix = $post->top_commentid && $post->top_commentid->id ? "c" : "p";
# 				$r->redirect("$bin/$board_folder_name#$prefix".$post->id);
# 			}

			# If use requested the folder name of a comment post instead of the actual post (The top comment), then redirect accordingly
			if($req->output_fmt ne 'json' && $post->top_commentid && $post->top_commentid->id)
			{
				#print STDERR "Top post, need redir, bin:$bin, binpath:".$self->binpath."\n";
				$r->redirect("$bin/$board_folder_name/".$post->top_commentid->folder_name."#c".$post->id);
			}
			
			#sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			my $dont_inc_comments = $req->no_comments == 1;
			my $post_resultset = $controller->load_post($post,$req,0,undef,$dont_inc_comments);
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($post_resultset);
				#return $r->output_data("application/json", $json);
				return $r->output_data("application/json", $json);
			}
			else
			{
				my $tmpl = $self->get_template($controller->config->{post_tmpl} || 'post.tmpl');
				$tmpl->param(board_nav => $controller->macro_board_nav());
				$tmpl->param( $_ => $post_resultset->{$_}) foreach keys %$post_resultset;
				$controller->apply_video_providers($tmpl);
				$tmpl->param(single_post_page => 1); # set a flag to differentiate this template from the list.tmpl in case the post.tmpl includes the same template needed to render posts in list.tmpl
				$tmpl->param(boards_indent_multiplier => $INDENT_MULTIPLIER);
				
				my $tmpl_incs = $controller->config->{tmpl_incs} || {};
				foreach my $key (keys %$tmpl_incs)
				{
					$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
				}
				
				my $view = Content::Page::Controller->get_view('sub',$r);
				$view->breadcrumb_list->push($board->title,"$bin/".$board->folder_name,0);
				$view->breadcrumb_list->push($post->subject,"$bin/".$board->folder_name."/".$post->folder_name,0);
				$view->output($tmpl);
				return $r;
			}
		}
	}
	
	sub to_folder_name
	{
		my $self = shift;
		my $fake_it = lc shift;
		my $disable_trim = shift || 0;
		$fake_it =~ s/['"\[\]\(\)]//g; #"'
		$fake_it =~ s/[^\w]/_/g;
		$fake_it =~ s/\_{2,}/_/g;
		$fake_it =~ s/(^\_+|\_+$)//g;
		
		if(length($fake_it) > $MAX_FOLDER_LENGTH && !$disable_trim)
		{
			my $idx = index($fake_it,"\n");
			my $len = $idx > -1 && $idx < $MAX_FOLDER_LENGTH ? $idx : $MAX_FOLDER_LENGTH;
			$fake_it = substr($fake_it,0,$len); # . (length($fake_it) > $len ? '...' : '');
		}
		return $fake_it;
		
	}
	
	sub send_notifications
	{
		my $self = shift;
		my $action = shift;
		my $object = shift;
		my $args = shift;
		
		# Actions:
		# - new_post ($post_ref)
		# - new_comment ($comment_ref, $comment_url)
		# - new_like ($like_ref, $noun)
		
		foreach my $method (qw/notify_via_email notify_via_facebook/)
		{
			$self->$method($action, $object, $args);
		}
	}
	
	sub notify_via_facebook
	{
		my $self = shift;
		my $action = shift;
		my $post = shift;
		my $args = shift;
		
		return if !$AppCore::Config::BOARDS_ENABLE_FB_NOTIFY || ($post->isa('Boards::Post') && (!$post->boardid->fb_sync_enabled || $post->data->get('user_said_no_fb')));
		
		if($action eq 'new_post' ||
		   $action eq 'new_comment')
		{
			my $really_upload = $args->{really_upload} || 0;
		
			if(!$really_upload)
			{
				# Flag this post object for later processing by boards_fb_poller
				$post->data->set('needs_uploaded',1);
				$post->data->update;
				return 1;
			}
			
			
			require LWP::UserAgent;
 			require LWP::Simple;
 
			my $board = $post->boardid;
			
			my $fb_feed_id	    = $board->fb_feed_id;
			my $fb_access_token = $board->fb_access_token;
			
			if(!$fb_feed_id || !$fb_access_token)
			{
				print STDERR "Unable to post notification for post# $post to Facebook - Feed ID or Access Token not found..\n";
				return;
			}
				
			my $notify_url = "https://graph.facebook.com/${fb_feed_id}/feed";
			print STDERR "Posting to Facebook URL $notify_url\n";
			
			my $ua = LWP::UserAgent->new;
			#$ua->env_proxy;
			
			my $board_folder = $post->boardid->folder_name;
			
			my $folder_name = $post->folder_name;
			my $board = $post->boardid;
			
			my $abs_url = $self->module_url("$board_folder/$folder_name" . ($action eq 'new_comment' ? "#c".$post->id:""),1);
			my $short_abs_url = $AppCore::Config::BOARDS_ENABLE_TINYURL_SHORTNER ? LWP::Simple::get("http://tinyurl.com/api-create.php?url=${abs_url}") : $abs_url;
			
			my $short_len = $AppCore::Config::BOARDS_SHORT_TEXT_LENGTH     || $SHORT_TEXT_LENGTH;
			my $short = AppCore::Web::Common->html2text($post->text);
			
			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
			
			my $quote = "\"".
				 substr($short,0,$short_len) . "\"" .
				(length($short) > $short_len ? '...' : '');
				
# 			my $message = $action eq 'new_post' ?
# 				"A new post was added by ".$post->poster_name." in ".$board->title." at $short_abs_url: $quote" :
# 				$post->poster_name.
# 				($post->parent_commentid && $post->parent_commentid->id ? " replied to ".$post->parent_commentid->poster_name : " commented ").
# 				" on \"".$post->top_commentid->subject."\" at $short_abs_url: $quote";

			my $message = $action eq 'new_post' ?
				$post->poster_name.": $quote - read more at $short_abs_url in '".$board->title."'":
				$post->poster_name.": $quote - ".
				($post->parent_commentid && $post->parent_commentid->id && $post->parent_comment->poster_name ne $post->poster_name ? " replied to ".$post->parent_commentid->poster_name : " commented ").
				" on \"".$post->top_commentid->subject."\" at $short_abs_url";
			
			
			my $photo = $post->poster_photo ? $post->poster_photo :
			            $post->posted_by ? $post->posted_by->photo : "";
			$photo = $AppCore::Config::WEBSITE_SERVER . $photo if $photo =~ /\//;
			
			my $form = 
			{
				access_token	=> $fb_access_token,
				message		=> $message,
				link		=> $abs_url,
				picture		=> $photo,
				name		=> $post->subject,
				caption		=> $action eq 'new_post' ? 
					"by ".$post->poster_name." in ".$board->title :
					"by ".$post->poster_name." on '".$post->top_commentid->subject."' in ".$board->title,
				description	=> $short_text,
				actions		=> qq|{"name": "View on the PHC Website", "link": "$abs_url"}|,
			};
			
			use Data::Dumper;
			print STDERR "Facebook post data: ".Dumper($form);
			
			my $response = $ua->post($notify_url, $form);
			
			if ($response->is_success) 
			{
				my $rs = decode_json($response->decoded_content);
				$post->external_id($rs->{id});
				$post->update;
				
				print STDERR "Facebook post successful, Facebook Post ID: ".$post->external_id."\n";
			}
			else 
			{
				print STDERR "ERROR Posting to facebook, message: ".$response->status_line."\nAs String:".$response->as_string."\n";
			}
		}
	}
	
	sub notify_via_email
	{
		my $self = shift;
		my $action = shift;
		my $post = shift;
		my $args = shift;
		
		#print STDERR "notify_via_email stacktrace:\n"; 
		#AppCore::Common::print_stack_trace();
		
		if($action eq 'new_post')
		{
# 			print STDERR __PACKAGE__."::email_new_post(): Disabled till email is enabled\n";
# 			return;
			
			my $board_folder = $post->boardid->folder_name;
			
			my $folder_name = $post->folder_name;
			my $board = $post->boardid;
			
			my $abs_url = $self->module_url("$board_folder/$folder_name",1);
			
			my $email_body = qq{A new post was added by }.$post->poster_name." in forum '".$board->title.qq{':

    }.AppCore::Web::Common->html2text($post->text).qq{

Here's a link to that page: 
    $abs_url
    
Cheers!};
			
			my @list = @AppCore::Config::ADMIN_EMAILS ? 
				   @AppCore::Config::ADMIN_EMAILS : 
				  ($AppCore::Config::WEBMASTER_EMAIL);
			
			# Dont email the person that just posted this :-)
			@list = grep { $_ ne $post->poster_email } @list;
			
			AppCore::EmailQueue->send_email([@list],"[$AppCore::Config::WEBSITE_NAME] ".$post->poster_name." posted in '".$board->title."'",$email_body) if @list;
		}
		elsif($action eq 'new_comment')
		{
			
# 			print STDERR __PACKAGE__."::email_new_post_comments(): Disabled till email is enabled\n";
# 			return;
			
			my $comment = $post;
			my $comment_url = $args->{comment_url} || $self->binpath ."/". $comment->boardid->folder_name . "/". $comment->top_commentid->folder_name."#c" . $comment->id;
			
			my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.AppCore::Web::Common->html2text($comment->text).qq{

Here's a link to that page: 
    ${AppCore::Config::WEBSITE_SERVER}$comment_url
    
Cheers!};
			#
			AppCore::EmailQueue->reset_was_emailed;
			
			my $noun = $self->config->{long_noun} || 'Bulletin Boards';
			my $title = $AppCore::Config::WEBSITE_NAME; 
			
			my @list = @AppCore::Config::ADMIN_EMAILS ? 
				   @AppCore::Config::ADMIN_EMAILS : 
				  ($AppCore::Config::WEBMASTER_EMAIL);
			
			my $email_subject = "[$title] ".$comment->poster_name." commented on '".$comment->top_commentid->subject."'";
			
			# Dont email the person that just posted this :-)
			@list = grep { $_ ne $comment->poster_email } @list;
			
			AppCore::EmailQueue->send_email([@list],$email_subject,$email_body);
			
			AppCore::EmailQueue->send_email([$comment->parent_commentid->poster_email],$email_subject,$email_body)
					if $comment->parent_commentid && 
					$comment->parent_commentid->id && 
					$comment->parent_commentid->poster_email &&
					$comment->parent_commentid->poster_email ne $comment->poster_email && 
					!AppCore::EmailQueue->was_emailed($comment->top_commentid->poster_email);
			
			AppCore::EmailQueue->send_email([$comment->top_commentid->poster_email],$email_subject,$email_body)
					if $comment->top_commentid && 
					$comment->top_commentid->id && 
					$comment->top_commentid->poster_email &&
					$comment->top_commentid->poster_email ne $comment->poster_email &&  
					!AppCore::EmailQueue->was_emailed($comment->top_commentid->poster_email);
			
			my $board = $comment->boardid;
			
			AppCore::EmailQueue->send_email([$board->managerid->email],$email_subject,$email_body)
						if $board && 
						$board->id && 
						$board->managerid && 
						$board->managerid->id && 
						$board->managerid->email && 
						$board->managerid->email ne $comment->poster_email &&
						!AppCore::EmailQueue->was_emailed($board->managerid->email);
						
			AppCore::EmailQueue->reset_was_emailed;
		}
		elsif($action eq 'new_like')
		{
			my $like = $post;
			my $noun = $args->{noun};
			
			my $comment_url = join('/', $self->binpath, $like->postid->boardid->folder_name, $like->postid->folder_name)."#c" . $like->postid->id;
			
			AppCore::EmailQueue->reset_was_emailed;
			
			my $noun = $self->config->{long_noun} || 'Bulletin Boards';
			my $title = $AppCore::Config::WEBSITE_NAME; 
			
			# Notify User
			my $email_subject = "[$title $noun] ".$like->name." likes your $noun '".$like->postid->subject."'";
			my $email_body = $like->name." likes your $noun '".$like->postid->subject."\n\n\t".
					AppCore::Web::Common->html2text($like->postid->text)."\n\n".
					"Here's a link to that page:\n".
					"\t${AppCore::Config::WEBSITE_SERVER}$comment_url\n\n".
					"Cheers!";
			
			AppCore::EmailQueue->send_email($like->postid->poster_email,$email_subject,$email_body) unless $like->postid->poster_email =~ /example\.com$/;
			
			# Notify Webmaster
			my @list = @AppCore::Config::ADMIN_EMAILS ? 
				   @AppCore::Config::ADMIN_EMAILS : 
				  ($AppCore::Config::WEBMASTER_EMAIL);
			
			$email_subject = "[$title $noun] ".$like->name." likes ".$like->postid->poster_name."'s $noun '".$like->postid->subject."'";
			$email_body = $like->name." likes ".$like->postid->poster_name."'s $noun '".$like->postid->subject."\n\n\t".
					AppCore::Web::Common->html2text($like->postid->text)."\n\n".
					"Here's a link to that page:\n".
					"\t${AppCore::Config::WEBSITE_SERVER}$comment_url\n\n".
					"Cheers!";
			
			AppCore::EmailQueue->send_email([@list],$email_subject,$email_body);
		}
	}
	
	sub log_spam
	{
		my $self = shift;
		my $text = shift;
		my $method = shift;
		my $notes = shift;
		my (undef,undef,undef,$sub) = caller(2); # log the second-level caller (the one that called is_spam)
		
		my $user = AppCore::Common->context->user;
		Boards::SpamLog->insert({
			userid		=> $user,
			subroutine	=> $sub,
			spam_method	=> $method,
			text		=> $text,
			extra_info	=> $notes
		});
		
		print STDERR "$sub: Trapped spam, method: '$method'\n";
	}
	
	sub is_spam
	{
		my $self = shift;
		my $text = shift;
		my $bot_trap = shift;
		
		my $user = AppCore::Common->context->user;
		
		# Admins automatically bypass spam filtering methods
		return 0 if $SPAM_OVERRIDE || ($user && $user->check_acl($self->config->{admin_acl}));
		
		### Method: 'Bot Trap' - hidden field, but it it has data, its probably a bot.
		if($bot_trap)
		{
			#print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$req->{comment}' [$req->{age}], sending to Wikipedia/Spam_(electronic)\n";
			$self->log_spam($text,'bot_trap');
			#PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
			return 1;
		}
		
		### Method: 'Empty Text' - Dont allow an empty or too-short text
		## TODO Make length configurable
		if(!$text || length($text) < 5)
		{
			$self->log_spam($text, 'empty');
			$@ = "It looks like you didn't type in anything - either the you left the text blank or the text was too short. Sorry!";
			return 1;
		}

		### Method: 'Banned Words' - Use word filtering lists from Dan's Guardian
		# Banned Words Filtering, Added 20090103 by JB
		{
			# Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
			my $clean = $text;
			$clean =~ s/<[^\>]*>//g; 
			$clean = AppCore::Web::Common->html2text($clean);
			$clean =~ s/[^\w]/ /g;
			$clean .= ' ';
			my ($weight,$matched) = Boards::BanWords::get_phrase_weight($clean);

			## TODO Make this a configurable threshold
			if($weight >= 5)
			{
				$self->log_spam($text,'ban_words',"Weight: $weight, Matched: ". join(", ",@$matched));
				$@ = "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try again.\nYour original comment:\n$text";
				return 1;
			}
		}

		### Method: 'No Links' - Ban including links if not a logged-in user
		if(	
			(!$user || !$user->id) &&
		        (
			$text =~ /(<a)/ig ||
			$text =~ /url=/   ||
			$text =~ /link=/))
		{
			#print STDERR "Debug Rejection: comment='$comment', commentor='$commentor'\n";
			#die "Sorry, you sound like a spam bot - go away. ($req->{comment})" if !$SPAM_OVERRIDE;
			$self->log_spam($text,'links');
			$@ = "Links aren't allowed, sorry";
			return 1;
		}
		
		return 0;
	}
	
	sub create_new_comment
	{
		my $self = shift;
		my $board = shift;
		my $post  = shift;
		my $req  = shift;
		my $user = shift;
		
		if($self->is_spam($req->{comment}, $req->{bot_trap}))
		{
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		if(!$req->{subject})
		{
			#my $text = AppCore::Web::Common->html2text($req->{comment});
			#$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
			$req->{subject} = $self->guess_subject($req->{comment});
		}
		
		my $fake_it = $self->to_folder_name($req->{subject});

		my $append_flag = 0;
		if(my $other = Boards::Post->by_field(folder_name => $fake_it))
		{
			$append_flag = 1;
		}
		
		#die Dumper($fake_it,$append_flag,$req);
		
		$user = AppCore::Common->context->user if !$user || !$user->id;
		if(!$user || !$user->id)
		{
			$req->{poster_name}  = 'Anonymous'          if !$req->{poster_name};
			$req->{poster_email} = 'nobody@example.com' if !$req->{poster_email};
		}
		else
		{
			$req->{poster_name}  = $user->display       if !$req->{poster_name};
			$req->{poster_email} = $user->email         if !$req->{poster_email};
		}
		
		my $photo = $req->{poster_photo};
		if(!$photo && $user && $user->id)
		{
			$photo = $user->photo;
		}
		
		my $comment = Boards::Post->create({
			boardid			=> $board,
			top_commentid		=> $req->{top_commentid} || $post,
			parent_commentid	=> $req->{parent_commentid},
			poster_name		=> $req->{poster_name},
			poster_email		=> $req->{poster_email},
			poster_photo		=> $photo,
			posted_by		=> $user,
			timestamp		=> date(),
			subject			=> $req->{subject},
			text			=> $req->{comment},
			folder_name		=> $fake_it,
		});
		
		if($append_flag)
		{
			$comment->folder_name($fake_it.'_'.$comment->id);
			$comment->update;
		}
		
		if(defined $req->{fb_post} && !$req->{fb_post})
		{
			$comment->data->set('user_said_no_fb',1);
			$comment->data->update;
		}
		
		return $comment;
	}
	
	sub load_post_reply_form
	{
		my $self = shift;
		my $post = shift;
		my $reply_to = shift;
		my $rs = {};
		$rs->{'post_'.$_} = $post->get($_) foreach $post->columns;
		
		if($reply_to)
		{
			my $parent = Boards::Post->by_field(folder_name=>$reply_to);
			   $parent = Boards::Post->retrieve($reply_to) 
			             if !$parent;
			
			# more fun with spam
			if(!$parent)
			{
# 				if($reply_to eq 'phc' && !$SPAM_OVERRIDE)
# 				{
# 					print STDERR "Debug: Ignoring apparent spammer, tried to load invalid URL, sending to Wikipedia/Spam_(electronic)\n";
# 					AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
# 				}
# 				else
				{
					die "Invalid parent $reply_to" if !$parent;
				}
			}
			
			
			$rs->{'reply_'.$_} = $parent->get($_) foreach $parent->columns;
			
			$rs->{subject} = 'Re: '.$parent->subject;
		}
		else
		{
			$rs->{subject} = 'Re: '.$post->subject;
		}
		
		return $rs;
	}
	
	sub post_delete
	{
		my $self = shift;
		my $post = shift;
		my $req = shift;
		
		if($req->{postid})
		{
			my $post = Boards::Post->retrieve($req->{postid});
			$post->deleted(1);
			$post->update;
			
			$post->top_commentid->num_replies($post->top_commentid->num_replies - 1);
			$post->top_commentid->update;
			
			return 'comment';
		}
		else
		{
			$post->top_commentid->num_replies($post->top_commentid->num_replies - 1);
			$post->top_commentid->update;
			
			$post->deleted(1);
			$post->update;
			return 'post';
		}
		
	}
	
	sub post_like
	{
		my $self = shift;
		my $post = shift;
		my $req = shift;
		my $user = shift;
		
		$user = AppCore::Common->context->user if !$user;
		$user = 0 if !$user || !$user->id;
		my $ref = Boards::Post::Like->insert({
			postid	=> $post->id,
			userid	=> $user,
			name	=> $user ? $user->display : '',
			email	=> $user ? $user->email : '',
			photo	=> $user ? $user->photo : '',
		});
		
		#print STDERR "post_like(): New like lineid $ref\n";
		
		my $noun = $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
		
		$self->send_notifications('new_like', $ref, {noun => $noun});
		
		return $noun;
	}
	
	sub post_unlike
	{
		my $self = shift;
		my $post = shift;
		my $req = shift;
		
		my $user = AppCore::Common->context->user;
		$user = 0 if !$user || !$user->id;
		return 'post' if !$user;
		
		Boards::Post::Like->search(  
			postid	=> $post->id,
			userid	=> $user
		)->delete_all;
		
		#print STDERR "post_like(): Unliked post $post\n";
		
		return $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
	}
	
	sub load_post_edit_form
	{
		my $self = shift;
		my $post = shift;
		my $board = $post->boardid;
		
		my $rs = {};
		$rs->{'post_'.$_}  = $post->get($_)  foreach $post->columns;
		$rs->{'board_'.$_} = $board->get($_) foreach $board->columns;
		
		$rs->{post_text} = AppCore::Web::Common->clean_html($rs->{post_text});
		
		return $rs;
	}
	
	sub post_edit_save
	{
		my $self = shift;
		my $post = shift;
		my $req = shift;
		
		if($self->is_spam($req->comment))
		{
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		if(!$req->{subject})
		{
			$req->{subject} = $self->guess_subject($req->{comment});
		}
		
		my $fake_it = $self->to_folder_name($req->{subject});
		if($fake_it ne $post->folder_name && Boards::Post->by_field(folder_name => $fake_it))
		{
			$fake_it .= '_'.$post->id;
		}
		
		#die Dumper $fake_it, $req;
		
		$post->subject($req->{subject});
		$post->text(AppCore::Web::Common->clean_html($req->{comment}));
		$post->folder_name($fake_it);
		$post->update;
		
		return $post;
	}
};

1;
