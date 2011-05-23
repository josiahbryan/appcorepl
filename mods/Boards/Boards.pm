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
			$$textref =~ s/([^'"\/<>])((?:(?:http|ftp|telnet|file):\/\/|www\.)([^\s<>'"]+))/$1<a href="$2">$2<\/a>/gi;
			
			#print STDERR "AutoLink: After: ".$$textref."\n";
		};
		
	};
	
package Boards::VideoProvider::YouTube;
	{
		use base 'Boards::VideoProvider';
		__PACKAGE__->register({
			name		=> "YouTube",						# Name isn't used currently
			provider_class	=> "video-youtube",					# provider_class is used in page to match provider to iframe template, and construct template and image ID's
			url_regex	=> qr/(http:\/\/www.youtube.com\/watch\?v=.+?\b)/,	# Used to find this provider's URL in content
			
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
			my ($code) = $url =~ /v=(.+?)\b/;
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
	
	# Inherit both a Web Module and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		AppCore::Web::Module
		Content::Page::Controller
	};
	
	# For making MD5's of emails
	use Digest::MD5 qw/md5_hex/;
	
	# For outputting JSON for new posts
	use JSON qw/encode_json decode_json/;
	
	# Contains all the data packages we need, such as Boards::Post, etc
	use Boards::Data;
	
	# The 'banned words' library which parses the Dan's Guardian words list
	use Boards::BanWords;
	
	our $SUBJECT_LENGTH    = 30;
	our $MAX_FOLDER_LENGTH = 225;
	our $SPAM_OVERRIDE     = 0;
	our $SHORT_TEXT_LENGTH = 60;
	our $LAST_POST_SUBJ_LENGTH = $SUBJECT_LENGTH;
	our $APPROX_TIME_REFERESH = 15; # seconds
	
	
	# Setup our admin package
	use Admin::ModuleAdminEntry;
	Admin::ModuleAdminEntry->register(__PACKAGE__, 'Boards', 'boards', 'List all boards on this site and manage boards settings.');
	
	# Register our pagetype
	__PACKAGE__->register_controller('Board Page','Bulletin Board Front Page',1,0,  # 1 = uses page path,  0 = doesnt use content
		[
			{ field => 'title',		type => 'string',	description => 'The title of the bulletin board' },
			{ field => 'tagline',		type => 'string',	description => 'A short description of the board' },
			{ field => 'description', 	type => 'text',		description => 'A long description of the board to appear on the board page itself' }, 
		]
	);
	
	# Setup the Web Module 
	sub DISPATCH_METHOD { 'main_page'}
	
	# Directly callable methods
	__PACKAGE__->WebMethods(qw{

	});

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
				
				# must define inorder to post notifications to a Facebook feed
				fb_feed_id	=> undef, # feed to notify
				fb_access_token	=> undef, # access token for given feed
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
		
		#print STDERR Dumper $self->config;
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
	
	
	sub board_page
	{
		my $self = shift;
		#my ($section_name,$folder_name,$skin,$r,$page,$req,$path) = @_;
		my $req = shift;
		my $r = shift;
		
		my $folder_name = $req->shift_path;
		
		$req->push_page_path($folder_name);
		
		my $board = Boards::Board->by_field(folder_name => $folder_name);
		if(!$board)
		{
			return $r->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		my $controller = $self;
		
		#die $board->folder_name;
		if($board->forum_controller)
		{
			eval 'use '.$board->forum_controller;
			die $@ if $@ && $@ !~ /Can't locate/;
			
			$controller = $board->forum_controller;
		}

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
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
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
			
			my @id_list = split /,/, $req->{id_list};
			
			my @posts = map { Boards::Post->retrieve($_) } @id_list;
			
			#sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			my @output_list = map { $self->load_post($_,$req,1) } @posts; # 1 = dont count this load as a 'view'
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
			return $controller->post_page($req,$r);
		}
		else
		{
			my $dbh = Boards::Post->db_Main;
			
			my $user = AppCore::Common->context->user;
			my $can_admin = $user && $user->check_acl($controller->config->{admin_acl}) ? 1 :0;
			my $board_folder_name = $board->folder_name;
			
			# Get the current pating location
			my $idx = $req->idx || 0;
			my $len = $req->len || $AppCore::Config::BOARDS_POST_PAGE_LENGTH;
			$len = $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH if $len > $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH;
			
			# Find the total number of posts in this board
			my $find_max_index_sth = $dbh->prepare_cached('select count(b.postid) as count from board_posts b where boardid=? and top_commentid=0 and deleted=0');
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
				# Used to clean up orphaned comments if the parent is deleted
				my $del_sth = $dbh->prepare_cached('update board_posts set deleted=1 where postid=?',undef,1);
				
				my $sth;
				
				if(!$len)
				{
					# If paging disabled, just use a single query to load everything
					$sth = $dbh->prepare_cached(q{
						select b.*, u.photo as user_photo from board_posts b left join users u on (b.posted_by=u.userid) where boardid=? and deleted=0 order by timestamp 
					});
				}
				else
				{
					# Paging not disabled, so first we get a list of postids (e.g. not the comments) to load - since the doing a limit (?,?) for comments would miss some ikder comments
					# that should be included because the post is included
					my $find_posts_sth = $dbh->prepare_cached('select b.postid from board_posts b where boardid=? and top_commentid=0 and deleted=0 order by timestamp desc limit ?,?');
					$find_posts_sth->execute($board->id, $idx, $len);
					my @posts;
					push @posts, $_ while $_ = $find_posts_sth->fetchrow;
					
					# Keep user from getting a "dirty" error by giving a simple error
					if(!@posts)
					{
						return $r->error("No posts at index ".($idx+0));
					}
					
					my $list = join ',',  @posts;
					
					# Now do the actual query that loads both posts and comments in one gos
					$sth = $dbh->prepare_cached('select b.*, u.photo as user_photo from board_posts b left join users u on (b.posted_by=u.userid) '.
						'where boardid=? and deleted=0 and '.
						'(postid in ('.$list.') or top_commentid in ('.$list.')) '.
						'order by timestamp');
				}
				
				$sth->execute($board->id);
				
				# First, prepare all the post results (posts and comments) at the same time
				# Create a crossref of posts to data objects for the next block which puts the comments with the parents
				my @tmp_list;
				my %crossref;
				while(my $b = $sth->fetchrow_hashref)
				{
					$crossref{$b->{postid}} = $b;
					$b->{reply_count} = 0;
					push @tmp_list, $controller->load_post_for_list($b,$board_folder_name,$can_admin);
				}
				
				# Now we put all the comments with the parent posts
				my @list;
				my %indents;
				foreach my $data (@tmp_list)
				{
					# This is a parent post, just add it to the master list
					if($data->{top_commentid} == 0)
					{
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
						$data->{indent_css}	= $indent * 2;
						
						# Lookup the top-most post for this comment
						# If its orphaned, we just delete the comment
						my $top_data = $crossref{$data->{top_commentid}};
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
	
				# Put newest at top of list
				# (We load oldest->newest so that we can process comments correctly, but reverse so newest top post is at the top, but comments still will show old->new)
				@list = reverse @list;
				
				$data = 
				{
					list 		=> \@list,
					timestamp	=> time,
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
				len	=> $len,
				idx2	=> $idx + $len,
				next_idx=> $next_idx,
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
			
			$tmpl->param($_ => $output->{$_}) foreach keys %$output;
			
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
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
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
			$hash->{user_photo} = $user->photo if $user && $user->id;
			
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
		
		my $cur_user = AppCore::Common->context->user;
		$b->{can_edit} = ($can_admin || ($cur_user && $cur_user->id == $b->{posted_by}) ? 1:0);
		
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
		#use Data::Dumper;
		#die Dumper \@TEXT_FILTERS;
		$b->{text}       = $self->create_video_links($text_tmp);
		$b->{clean_html} = $self->create_video_links($clean_html);
		
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
		
		
		my $folder_name = $post->folder_name;
 		my $board_folder_name 
 		              = $post->boardid->folder_name;
		my $bin       = $self->binpath();
		
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
			my $sth = Boards::Post->db_Main->prepare_cached('select b.*, u.photo as user_photo from board_posts b left join users u on (b.posted_by=u.userid) '.
				'where deleted=0 and '.
				'top_commentid=? '.
				'order by timestamp');
		
			$sth->execute($post->id);
			
			# First, prepare all the post results (posts and comments) at the same time
			my @tmp_list;
			while(my $b = $sth->fetchrow_hashref)
			{
				push @tmp_list, $self->load_post_for_list($b,$board_folder_name,$can_admin);
			}
			
			my $board = $post->boardid;
			$post_ref = $self->load_post_for_list($post,$board->folder_name,$can_admin);
			$post_ref->{'board_'.$_} = $board->get($_)."" foreach $board->columns;
			$post_ref->{'post_' .$_} = $post_ref->{$_}."" foreach $post->columns;
			$post_ref->{reply_count}  = 0;
			
			# Now we put all the comments with the parent posts
			my @list;
			my %indents;
			foreach my $data (@tmp_list)
			{
				# This is a comment, so we need to calculate an "indent" value 
				# for the template to use to indet the comment
				
				my $parent_comment = $data->{parent_commentid};
				my $indent = $indents{$parent_comment} || 0;
				my $id     = $data->{postid};
				
				$data->{indent}		= $indent;
				$data->{indent_css}	= $indent * 2;
				
				# Add the comment to the post
				push @{$post_ref->{replies}}, $data;
				
				$post_ref->{reply_count} ++;
				$indents{$id} = $indent + 1; 
			}
	
			$PostDataCache{$cache_key} = $post_ref;
		}
		
		return $post_ref;
	}
	
	sub can_user_edit
	{
		my $self = shift;
		my $post = shift;
		local $_;
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		
		return $can_admin || (($_ = AppCore::Common->context->user) && $post->posted_by && $_->userid == $post->posted_by->id);
			
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
			my $text = AppCore::Web::Common->html2text($req->{comment});
			#$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
			my $idx = index($text,"\n");
			my $len = $idx > -1 && $idx < $SUBJECT_LENGTH ? $idx : $SUBJECT_LENGTH;
			$req->{subject} = substr($text,0,$len) . ($idx < 0 && length($text) > $len ? '...' : '');
		}
		
		my $fake_it = $self->to_folder_name($req->{subject});
		
		my $append_flag = 0;
		if(my $other = Boards::Post->by_field(folder_name => $fake_it))
		{
			$append_flag = 1;
		}
		
		$req->{poster_name}  = 'Anonymous'          if !$req->{poster_name};
		$req->{poster_email} = 'nobody@example.com' if !$req->{poster_email};
		
		# Try to guess if HTML is really just text
		if(!might_be_html($req->{comment}) || $req->{plain_text})
		{
			$req->{comment} = text2html($req->{comment});
		}
		
		$user = AppCore::Common->context->user if !$user;
		
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
		});
		
		if($append_flag)
		{
			$fake_it = $fake_it.'_'.$post->id;
			$post->folder_name($fake_it);
			$post->update;
		}
		
		return $post;
			
	}
	
	sub post_page
	{
		my $self  = shift;
		my $req   = shift;
		my $r     = shift;
		
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
			my $comment     = $self->create_new_comment($board,$post,$req);
			my $comment_url = "$bin/$board_folder_name/$folder_name#c" . $comment->id;
			
			$self->send_notifications('new_comment',$comment,{comment_url => $comment_url});
			
			print STDERR __PACKAGE__."::post_page($post): Posted reply ID $comment to post ID $post\n";
			
			if($req->output_fmt eq 'json')
			{
				# NOTE: $self in this case WILL be the 'controller' for $board,
				# because post_page() is called as $controller->post_page(...)  -
				# Therefore, we dont need to call it by $board->controller ourself 
				# - $self is already set correctly.
				my $output = $self->load_post_for_list($comment,$board->folder_name);
				
				my $json = encode_json($output);
				return $r->output_data("application/json", $json);
			}
			
			$r->redirect($comment_url);
		}
		elsif($sub_page eq 'reply' || $sub_page eq 'reply_to')
		{
			my $tmpl = $self->get_template($self->config->{post_reply_tmpl} || 'post_reply.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			eval
			{
				my $reply_form_resultset = $self->load_post_reply_form($post,$req->shift_path);
				$tmpl->param($_ => $reply_form_resultset->{$_}) foreach keys %$reply_form_resultset;
			};
			$r->error("Error Loading Form",$@) if $@;
			#$r->error("No Such Post","Sorry, the parent comment you gave appears to be invalid.");
			
			$tmpl->param(post_url => "$bin/$board_folder_name/$folder_name/post");
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
				
		}
		elsif($sub_page eq 'delete')
		{
			if(!$self->can_user_edit($post))
			{
				PHC::User::Auth->require_authentication($self->config->{admin_acl});
			}
			
			my $type = $self->post_delete($post,$req);
			
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
			my $type = $self->post_like($post,$req);
			
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
			my $type = $self->post_unlike($post,$req);
			
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
			if(!$self->can_user_edit($post))
			{
				$r->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			my $tmpl = $self->get_template($self->config->{new_post_tmpl} || 'new_post.tmpl');
			
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('folder_'.$board_folder_name => 1);
			
			my $edit_resultset = $self->load_post_edit_form($post);
			$tmpl->param($_ => $edit_resultset->{$_}) foreach keys %$edit_resultset;
			
			$tmpl->param(post_url => "$bin/$board_folder_name/$folder_name/save");
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'save')
		{
			if(!$self->can_user_edit($post))
			{
				$r->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			$self->post_edit_save($post,$req);
			
			my $folder = $post->folder_name;
			
			my $abs_url = $self->module_url("$board_folder_name/$folder",1);
			
			my $email_body = $post->poster_name." edited post '".$post->subject."' in forum '".$board->title.qq{':

    }.AppCore::Web::Common->html2text($req->{comment}).qq{

Here's a link to that page: 
    $abs_url
    
Cheers!};
			my @list = @AppCore::Config::ADMIN_EMAILS ? 
			           @AppCore::Config::ADMIN_EMAILS : 
			          ($AppCore::Config::WEBMASTER_EMAIL);
			AppCore::Web::Common->send_email([@list],"[$AppCore::Config::WEBSITE_NAME] Post Edited: '".$post->subject."' in forum '".$board->title."'",$email_body);
		
			$r->redirect("$bin/$board_folder_name/".$post->folder_name);
				
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
				$r->redirect("$bin/$board_folder_name/".$post->top_commentid->folder_name."#c".$post->id);
			}
			
			#sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			my $dont_inc_comments = $req->no_comments == 1;
			my $post_resultset = $self->load_post($post,$req,0,undef,$dont_inc_comments);
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($post_resultset);
				#return $r->output_data("application/json", $json);
				return $r->output_data("application/json", $json);
			}
			else
			{
				
				my $tmpl = $self->get_template($self->config->{post_tmpl} || 'post.tmpl');
				$tmpl->param(board_nav => $self->macro_board_nav());
				$tmpl->param( $_ => $post_resultset->{$_}) foreach keys %$post_resultset;
				
				my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
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
		
		return if !$AppCore::Config::BOARDS_ENABLE_FB_NOTIFY;
		
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
			
			my $short_len = 160; #$AppCore::Config::BOARDS_SHORT_TEXT_LENGTH     || $SHORT_TEXT_LENGTH;
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
				($post->parent_commentid && $post->parent_commentid->id ? " replied to ".$post->parent_commentid->poster_name : " commented ").
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
			print STDERR __PACKAGE__."::email_new_post(): Disabled till email is enabled\n";
			return;
			
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
			AppCore::Web::Common->send_email([@list],"[$AppCore::Config::WEBSITE_NAME] New Post Added to Forum '".$board->title."'",$email_body);
		}
		elsif($action eq 'new_comment')
		{
			
			print STDERR __PACKAGE__."::email_new_post_comments(): Disabled till email is enabled\n";
			return;
			
			my $comment = $post;
			my $comment_url = $args->{comment_url};
			
			my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.AppCore::Web::Common->html2text($comment->text).qq{

Here's a link to that page: 
    ${AppCore::Config::WEBSITE_SERVER}$comment_url
    
Cheers!};
			#
			AppCore::Web::Common->reset_was_emailed;
			
			my $noun = $self->config->{long_noun} || 'Bulletin Boards';
			my $title = $AppCore::Config::WEBSITE_NAME; 
			
			my @list = @AppCore::Config::ADMIN_EMAILS ? 
				   @AppCore::Config::ADMIN_EMAILS : 
				  ($AppCore::Config::WEBMASTER_EMAIL);
			
			my $email_subject = "[$title $noun] New Comment Added to Thread '".$comment->top_commentid->subject."'";
			AppCore::Web::Common->send_email([@list],$email_subject,$email_body);
			
			AppCore::Web::Common->send_email([$comment->parent_commentid->poster_email],$email_subject,$email_body)
					if $comment->parent_commentid && 
					$comment->parent_commentid->id && 
					$comment->parent_commentid->poster_email && 
					!AppCore::Web::Common->was_emailed($comment->top_commentid->poster_email);
			
			AppCore::Web::Common->send_email([$comment->top_commentid->poster_email],$email_subject,$email_body)
					if $comment->top_commentid && 
					$comment->top_commentid->id && 
					$comment->top_commentid->poster_email && 
					!AppCore::Web::Common->was_emailed($comment->top_commentid->poster_email);
			
			my $board = $comment->boardid;
			
			AppCore::Web::Common->send_email([$board->managerid->email],$email_subject,$email_body)
						if $board && 
						$board->id && 
						$board->managerid && 
						$board->managerid->id && 
						$board->managerid->email && 
						!AppCore::Web::Common->was_emailed($board->managerid->email);
						
			AppCore::Web::Common->reset_was_emailed;
		}
		elsif($action eq 'new_like')
		{
			my $like = $post;
			my $noun = $args->{noun};
			
			my $comment_url = join('/', $self->binpath, $like->postid->boardid->folder_name, $like->postid->folder_name)."#c" . $like->postid->id;
			
			#AppCore::Web::Common->reset_was_emailed;
			
			my $noun = $self->config->{long_noun} || 'Bulletin Boards';
			my $title = $AppCore::Config::WEBSITE_NAME; 
			
			# Notify User
			my $email_subject = "[$title $noun] ".$like->name." likes your $noun '".$like->postid->subject."'";
			my $email_body = $like->name." likes your $noun '".$like->postid->subject."\n\n\t".
					AppCore::Web::Common->html2text($like->postid->text)."\n\n".
					"Here's a link to that page:\n".
					"\t${AppCore::Config::WEBSITE_SERVER}$comment_url\n\n".
					"Cheers!";
			
			AppCore::Web::Common->send_email($like->postid->poster_email,$email_subject,$email_body) unless $like->postid->poster_email =~ /example\.com$/;
			
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
			
			AppCore::Web::Common->send_email([@list],$email_subject,$email_body);
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
			my $text = AppCore::Web::Common->html2text($req->{comment});
			$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
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
