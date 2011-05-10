use strict;
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
	
	our $SUBJECT_LENGTH    = 30;
	our $MAX_FOLDER_LENGTH = 225;
	our $SPAM_OVERRIDE     = 0;
	our $SHORT_TEXT_LENGTH = 60;
	our $LAST_POST_SUBJ_LENGTH = $SUBJECT_LENGTH;
	
	# Setup our admin package
	# TODO #
	#use Admin::ModuleAdminEntry;
	#Admin::ModuleAdminEntry->register(__PACKAGE__, 'Boards', 'boards', 'List all boards on this site and manage the user-created content.');
	# TODO #
	
	# Register our pagetype
	__PACKAGE__->register_controller('Board Page','Bulliten Board Front Page',1,0,  # 1 = uses page path,  0 = doesnt use content
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
	
	our %BoardDataCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
		%BoardDataCache = ();
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
			
			$controller->email_new_post($post);
			#$r->redirect(AppCore::Common->context->http_bin."/$section_name/$folder_name#c$post");
			
			if($req->output_fmt eq 'json')
			{
				my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
				
				#$b->{text} = PHC::VerseLookup->tag_verses($b->{text});
				
				my $b = $controller->load_post_for_list($post,$board->folder_name,$can_admin);
				
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
			
			my $tmpl = $self->get_template($controller->config->{list_tmpl} || 'list.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			
			my $user = AppCore::Common->context->user;
			my $can_admin = 1 if $user && $user->check_acl($controller->config->{admin_acl});
			$tmpl->param(can_admin=>$can_admin);
			
			#my @posts = Boards::Post->search(deleted=>0,boardid=>$board,top_commentid=>0);
			#my $boardid = $board->id + 0;
			#my @posts = Boards::Post->retrieve_from_sql("deleted=0 and boardid=$boardid and top_commentid=0 order by timestamp desc");
			#@posts = sort {$b->timestamp cmp $a->timestamp} @posts;
			#@posts = shift @posts;
			my $cache_key = $user ? $board->id . $user->id : $board->id;
			my $list = $BoardDataCache{$cache_key};
			if(!$list)
			{
				my $sth = Boards::Post->db_Main->prepare(q{
					select b.*, u.photo as user_photo from board_posts b left join users u on (b.posted_by=u.userid) where boardid=? and deleted=0 order by timestamp 
				});
				$sth->execute($board->id);
				my $board_folder_name = $board->folder_name;
				my @tmp_list;
				my %crossref;
				while(my $b = $sth->fetchrow_hashref)
				{
					$crossref{$b->{postid}} = $b;
					$b->{reply_count} = 0;
					push @tmp_list, $controller->load_post_for_list($b,$board_folder_name,$can_admin);
				}
				
				my @list;
				my %indents;
				foreach my $data (@tmp_list)
				{
					if($data->{top_commentid} == 0)
					{
						push @list, $data;
					}
					else
					{
						my $parent_comment = $data->{parent_commentid};
						my $indent = $indents{$parent_comment} || 0;
						my $id     = $data->{postid};
						
						$data->{indent}		= $indent;
						$data->{indent_css}	= $indent * 2;
						
						my $top_data = $crossref{$data->{top_commentid}};
						if(!$top_data)
						{
							print STDERR "Odd: Orphaned child $data->{postid} - has top commentid $data->{top_commentid} but not in crossref!";
						}
						else
						{
							push @{$top_data->{replies}}, $data;
						}
			
						$top_data->{reply_count} ++;
						$indents{$id} = $indent + 1; 
					}	
				}
	
				# Put newest at top of list
				@list = reverse @list;
				
				$list = \@list;
				$BoardDataCache{$cache_key} = $list;
				print STDERR "[-] BoardDataCache Cache Miss for board $board (key: $cache_key)\n"; 
				
				#die Dumper \@list;
			}
			else
			{
				#print STDERR "[+] BoardDataCache Cache Hit for board $board\n";
			}
			
			$tmpl->param(posts=>$list);
			
			$controller->forum_page_hook($tmpl,$board);
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
	}
	
	sub load_post_for_list
	{
		my $self = shift;
		my $post = shift;
		my $board_folder_name = shift;
		my $can_admin = shift || 0;
		my $dont_incl_comments = shift || 0;
		
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
		
		## NOTE Assuming SQL query already provided all user columns as user_*
# 		if($user && $user->id)
# 		{
# 			@cols = $user->columns;
# 			$b->{'user_'.$_} = $user->get($_) foreach @cols; #$user->columns;
# 		}
	
		#timemark();
		my $short = AppCore::Web::Common->html2text($b->{text});
		$b->{short_text}  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
		$b->{short_text_has_more} = length($short) > $short_len;
		
		$b->{clean_html} = $b->{short_text};
		$b->{clean_html} =~ s/\n+/\n/sg;
		$b->{clean_html} =~ s/\n/<br>\n/g;
		$b->{clean_html} =~ s/<br>\s*\n\s*<br>\s*\n\s*<br>\s*\n/<br>\n/sg;
		
		#$b->{short_text_html} =~ s/([^'"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/$1<a href="$1">$2<\/a>/gi;
		$b->{clean_html} =~ s/(?<!(\ssrc|href)=['"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/<a href="$2">$2<\/a>/gi;
		my ($url) = $b->{clean_html} =~ /(http:\/\/www.youtube.com\/watch\?v=.+?\b)/;
		if($url)
		{
			my ($code) = $url =~ /v=(.+?)\b/;
			#$b->{short_text_html} .= '<hr size=1><iframe title="YouTube video player" width="320" height="240" src="http://www.youtube.com/embed/'.$code.'" frameborder="0" allowfullscreen></iframe>';;
			$b->{clean_html} .= qq{
				<hr size=1 class='post-attach-divider'>
				<a href='$url' class='youtube-play-link' videoid='$code'>
				<img src="http://img.youtube.com/vi/$code/1.jpg" border=0>
				<span class='overlay'></span>
				</a>
			};
		}
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
		#use Data::Dumper;
		#die Dumper $b if $b->{you_like};
			
		
# 		$b->{$_} = $b->get($_) foreach $b->columns;
# 		$b->{bin}         = $bin;
# 		$b->{appcore}     = $appcore;
# 		$b->{board_folder_name} = $folder_name;
# 		$b->{can_admin}   = $can_admin;
# 		my $short = AppCore::Web::Common->html2text($b->{text});
# 		$b->{short_text}  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
# 		$b->{short_text_has_more} = length($short) > $short_len;
# 		$b->{short_text_html} = $b->{short_text};
# 		$b->{short_text_html} =~ s/\n/<br>\n/g;
# 		$b->{folder_name} = $b->folder_name;
# 		$b->{poster_email_md5} = md5_hex($b->{poster_email});
		
# 		if($dont_incl_comments)
# 		{
# 			my $lc = $post->last_commentid;
# 			if($lc && $lc->id && !$lc->deleted)
# 			{
# 				$b->{'post_'.$_} = $lc->get($_)."" foreach $lc->columns;
# 				$b->{post_subject} = substr($b->{post_subject},0,$last_post_subject_len) . (length($b->{post_subject}) > $last_post_subject_len ? '...' : '');
# 				$b->{post_url} = "$bin/$board_folder_name/$folder_name#c$lc";
# 				$b->{post_poster_email_md5} = md5_hex($lc->poster_email);
# 			}
# 		}
# 		else
		{
			my $list = [];
			
			# TODO Process comments
			my $local_ctx = 
			{
				post		=> $post,
				bin		=> $bin,
				appcore		=> $AppCore::Config::WWW_ROOT,
				board_folder	=> $board_folder_name,
				folder_name	=> $folder_name,
				reply_to_url	=> $reply_to_url,
				can_admin	=> $can_admin,
				delete_base	=> $delete_base,
			};
			
# 			if($more_local_ctx && ref($more_local_ctx) eq 'HASH')
# 			{
# 				$local_ctx->{$_} = $more_local_ctx->{$_} foreach keys %$more_local_ctx;
# 			}
			
# 			my @replies = Boards::Post->search(deleted=>0,top_commentid=>$post,parent_commentid=>0);
# 			foreach my $b (@replies)
# 			{
# 				push @$list, _post_prep_ref($local_ctx,$b);
# 				_post_add_kids($local_ctx,$list,$b);
# 			}
			
			$b->{replies} = $list;
		}
		
		#$b->{text} = PHC::VerseLookup->tag_verses($b->{text});
		
		return $b;
	}
	
	# This allows subclasses to hook into the list prep above without subclassing the entire list action
	sub forum_list_hook#($post)
	{}
	sub forum_page_hook#($tmpl,$board)
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
		
		my $rs = {};
		
		my $board = $post->boardid;
		# Force stringification in order to convert to JSON if needed
		$rs->{'post_'.$_}  = $post->get($_).""  foreach $post->columns;
		$rs->{'board_'.$_} = $board->get($_)."" foreach $board->columns;
		
		$rs->{post_text} = AppCore::Web::Common->clean_html($rs->{post_text});
		
		#$rs->{post_text} = PHC::VerseLookup->tag_verses($rs->{post_text});
		
		my $reply_to_url = "$bin/$board_folder_name/$folder_name/reply_to";
		my $delete_base  = "$bin/$board_folder_name/$folder_name/delete";
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		$rs->{can_admin} = $can_admin;
		
		$rs->{can_edit} = $self->can_user_edit($post);
		
		unless($dont_incl_comments)
		{
			my $list = [];
			
			my $local_ctx = 
			{
				post		=> $post,
				bin		=> $bin,
				appcore		=> $AppCore::Config::WWW_ROOT,
				board_folder	=> $board_folder_name,
				folder_name	=> $folder_name,
				reply_to_url	=> $reply_to_url,
				can_admin	=> $can_admin,
				delete_base	=> $delete_base,
			};
			
			if($more_local_ctx && ref($more_local_ctx) eq 'HASH')
			{
				$local_ctx->{$_} = $more_local_ctx->{$_} foreach keys %$more_local_ctx;
			}
			
			my @replies = Boards::Post->search(deleted=>0,top_commentid=>$post,parent_commentid=>0);
			foreach my $b (@replies)
			{
				push @$list, _post_prep_ref($local_ctx,$b);
				_post_add_kids($local_ctx,$list,$b);
			}
			
			$rs->{replies} = $list;
		}
		
		return $rs;
	}
	
	sub can_user_edit
	{
		my $self = shift;
		my $post = shift;
		local $_;
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		
		return $can_admin || (($_ = AppCore::Common->context->user) && $post->posted_by && $_->userid == $post->posted_by->id);
			
	}
	
	sub _post_prep_ref
	{
		my $local_ctx = shift;
		my $comment = shift;
		my $b = {};
		my $user = $comment->posted_by;
		# Force stringify for JSON
		$b->{$_} = $comment->get($_).""   foreach $comment->columns;
		$b->{$_} = $local_ctx->{$_}."" foreach keys %$local_ctx;
		$b->{indent}		= $local_ctx->{indent}->{$comment->parent_commentid};
		$b->{indent_css} 	= $b->{indent} * 2;
		$b->{can_reply}		= defined $local_ctx->{can_reply} ? $local_ctx->{can_reply} : 1,
		$b->{approx_time_ago}   = approx_time_ago($b->{timestamp});
		$b->{pretty_timestamp}  = pretty_timestamp($b->{timestamp});
		$b->{post_poster_email_md5} = md5_hex($b->{poster_email});
		
		$b->{user_photo}	= $user && ref $user && $user->id ? $user->photo : "";
		#print STDERR "_post_prep_ref: \$user: $user, photo:".$b->{user_photo}.", ref:".ref($user).", ref eml:$b->{poster_email}\n";
		
		$b->{text} 		=~ s/(^\s+|\s+$)//g;
		$b->{text} 		=~ s/(^<p>|<\/p>$)//g; #unless index(lc $b->{text},'<p>') > 0;
		#$b->{text}		=~ s/((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/<a href="$1">$1<\/a>/gi;
		$b->{clean_html} = $b->{text};
		$b->{clean_html} =~ s/(?<!(\ssrc|href)=['"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/<a href="$2">$2<\/a>/gi;
		my ($url) = $b->{clean_html} =~ /(http:\/\/www.youtube.com\/watch\?v=.+?\b)/;
		if($url)
		{
			my ($code) = $url =~ /v=(.+?)\b/;
			#$b->{short_text_html} .= '<hr size=1><iframe title="YouTube video player" width="320" height="240" src="http://www.youtube.com/embed/'.$code.'" frameborder="0" allowfullscreen></iframe>';;
			$b->{clean_html} .= qq{
				<hr size=1 class='post-attach-divider'>
				<a href='$url' class='youtube-play-link' videoid='$code'>
				<img src="http://img.youtube.com/vi/$code/1.jpg" border=0>
				<span class='overlay'></span>
				</a>
			};
		}
		
		my ($code) = $b->{clean_html} =~ /vimeo\.com\/(\d+)/;
		if($code)
		{
			$b->{clean_html} .= qq{
				<hr size=1 class='post-attach-divider'>
				<a href='http://www.vimeo.com/$code' isvimeo="1" class='vimeo-video youtube-play-link' videoid='$code'>
				<img src="" id="vimeo-$code" border=0>
				<span class='overlay'></span>
				</a>
			};
		}
		
		#$b->{text}		= PHC::VerseLookup->tag_verses($b->{text});
		$local_ctx->{indent}->{$comment->id} = $b->{indent} + 1;
		#push @$list, $b;
		return $b;
	}
	
	sub _post_add_kids
	{
		my $local_ctx = shift;
		my $list = shift;
		my $b = shift;
		my @kids = Boards::Post->search(deleted=>0,top_commentid=>$local_ctx->{post},parent_commentid=>$b);
		foreach my $kid (@kids)
		{
			push @$list, _post_prep_ref($local_ctx,$kid);
			_post_add_kids($local_ctx,$list,$kid);
		}
	}
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;

		#print STDERR "create_new_thread: \$SPAM_OVERRIDE=$SPAM_OVERRIDE, args:".Dumper($req);
		
		## TODO ## Add bottrick hidden field filtering in generic fashion
# 		# Comment is now hidden, 20090716 JB
# 		# If it has data, then its probably spam. The visible comment field is named "age"
# 		if($req->{comment} && !$req->{_internal_} && !$SPAM_OVERRIDE)
# 		{
# 			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$req->{comment}' [$req->{age}], sending to Wikipedia/Spam_(electronic)\n";
# 			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
# 		}
		
# 		#die Dumper $req;
# 		# Now copy the data over to the proper field so I dont have to patch all the code below
# 		$req->{comment} = $req->{age};# if !$req->{_internal_};

		## TODO ## Add generic empty text filtering
# 		if(!$req->{comment} || length($req->{comment}) < 5)
# 		{
# 			return PHC::Web::Skin->instance->error("No Text Given!","You must enter *something* in the text box! [3]");
#            	}

		## TODO ## Add generic banned word filtering
# 		# Banned Words Filtering, Added 20090103 by JB
# 		{
# 			require 'ban_words_lib.pl';
# 			# Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
# 			my $clean = $req->{comment};
# 			$clean =~ s/<[^\>]*>//g; 
# 			$clean = AppCore::Web::Common->html2text($clean);
# 			$clean =~ s/[^\w]/ /g;
# 			$clean .= ' ';
# 			my ($weight,$matched) = PHC::BanWords::get_phrase_weight($clean);
# 
# 			my $user = AppCore::Common->context->user;
# 
# 
# 			if($weight >= 5)
# 			{
# 				PHC::Chat->db_Main->do('insert into chat_rejected (posted_by,poster_name,message,value,list) values (?,?,?,?,?)',undef,
# 					$user,
# 					$user && $user->id ? $user->display : $req->{poster_name},
# 					$req->{comment},
# 					$weight,
# 					join("\n ",@$matched)
# 				);
# 
# 				print STDERR "===== BANNED ====\nPhrase: '$req->{comment}'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n================\n";
# 				die "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try again.\nYour original comment:\n$req->{comment}";		
# 			}
# 		}

		
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
		
		$req->{poster_name}  = 'Anonymous'          if !$req->{poster_name};
		$req->{poster_email} = 'nobody@example.com' if !$req->{poster_email};
		
		my $post = Boards::Post->create({
			boardid			=> $board->id,
			poster_name		=> $req->{poster_name},
			poster_email		=> $req->{poster_email},
			posted_by		=> AppCore::Common->context->user,
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
	
	sub email_new_post
	{
		print STDERR __PACKAGE__."::email_new_post(): Disabled till email is enabled\n";
		return;
		
		my $self = shift;
		my $post = shift;
		my $board_folder = $post->boardid->folder_name;
		
		my $folder_name = $post->folder_name;
		my $board = $post->boardid;
		
		my $abs_url = $self->module_url("$board_folder/$folder_name");
		
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
			
			$self->email_new_post_comments($comment,$comment_url);
			
			print STDERR __PACKAGE__."::post_page($post): Posted reply ID $comment to post ID $post\n";
			
			if($req->output_fmt eq 'json')
			{
				my $list = [];
			
				my $reply_to_url = "$bin/$board_folder_name/$folder_name/reply_to";
				my $delete_base  = "$bin/$board_folder_name/$folder_name/delete";
			
				my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});;
				
				my $local_ctx = 
				{
					post		=> $post,
					bin		=> $bin,
					appcore		=> $AppCore::Config::WWW_ROOT,
					board_folder	=> $board_folder_name,
					folder_name	=> $folder_name,
					reply_to_url	=> $reply_to_url,
					can_admin	=> $can_admin,
					delete_base	=> $delete_base,
				};
				
				my $output = _post_prep_ref($local_ctx,$comment);
				
# 				use Data::Dumper;
# 				print STDERR Dumper $output;
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
			
			my $abs_url = $self->module_url("$board_folder_name/$folder");
			
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
			if($post->top_commentid && $post->top_commentid->id)
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
		$fake_it = substr($fake_it,0,$MAX_FOLDER_LENGTH) if length($fake_it) > $MAX_FOLDER_LENGTH && !$disable_trim;
		return $fake_it;
		
	}
	
	sub email_new_post_comments
	{
		print STDERR __PACKAGE__."::email_new_post_comments(): Disabled till email is enabled\n";
		return;
		
		my $self = shift;
		my $comment = shift;
		my $comment_url = shift;
		
		my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.AppCore::Web::Common->html2text($comment->text).qq{

Here's a link to that page: 
    ${AppCore::Config::WEBSITE_SERVER}$comment_url
    
Cheers!};
		#
		AppCore::Web::Common->reset_was_emailed;
		
		my $noun = $self->config->{long_noun} || 'Bulletin Boards';
		
		my @list = @AppCore::Config::ADMIN_EMAILS ? 
			   @AppCore::Config::ADMIN_EMAILS : 
			  ($AppCore::Config::WEBMASTER_EMAIL);
		my $title = $AppCore::Config::WEBSITE_NAME; 
		
		
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
	
	sub create_new_comment
	{
		my $self = shift;
		my $board = shift;
		my $post  = shift;
		my $req  = shift;
		
		
		## TODO ## Add bottrick field filtering
# 		# Comment is now hidden, 20090716 JB
# 		# If it has data, then its probably spam. The visible comment field is named "age"
# 		if($req->{comment} && !$req->{_internal_} && !$SPAM_OVERRIDE)
# 		{
# 			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$req->{comment}' [$req->{age}], sending to Wikipedia/Spam_(electronic)\n";
# 			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
# 		}
# 		
# 		# Now copy the data over to the proper field so I dont have to patch all the code below
# 		$req->{comment} = $req->{age} if !$req->{_internal_};

		## TODO ## Add empty text filtering
		if(!$req->{comment} || length($req->{comment}) < 5)
		{
			return PHC::Web::Skin->instance->error("Empty Comment!","You must enter *something* to comment! [1]");
		}

		
		## TODO ## Add banned word filtering
# 		# Banned Words Filtering, Added 20090103 by JB
#                 {
# 			require 'ban_words_lib.pl';
# 			# Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
# 			my $clean = $req->{comment};
# 			$clean =~ s/<[^\>]*>//g; $clean = AppCore::Web::Common->html2text($clean);
# 			$clean =~ s/[^\w]/ /g;
# 			$clean .= ' ';
# 			my ($weight,$matched) = PHC::BanWords::get_phrase_weight($clean);
# 
# 			my $user = AppCore::Common->context->user;
# 
# 
# 			if($weight >= 5)
# 			{
# 				PHC::Chat->db_Main->do('insert into chat_rejected (posted_by,poster_name,message,value,list) values (?,?,?,?,?)',undef,
# 					$user,
# 					$user && $user->id ? $user->display : $req->{poster_name},
# 					$req->{comment},
# 					$weight,
# 					join("\n ",@$matched)
# 				);
# 
# 				print STDERR "===== BANNED ====\nPhrase: '$req->{comment}'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n======
# ==========\n";
# 				die "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try
# again.\nYour original comment:\n$req->{comment}";
# 			}
# 			
# 			#die "CLEAN:".Dumper ($req,$weight,$matched,$clean);
#                 }
		
		
		## TODO Make link rejection configurable/disableable as needed
		my @tag = $req->{comment} =~ /(<a)/ig;
			
		if(
			$req->{poster_name} =~ /\d{2,}/ ||
			$req->{comment} =~ /url=/ ||
			$req->{comment} =~ /link=/ ||
			@tag >= 1)
		{
			#print STDERR "Debug Rejection: comment='$comment', commentor='$commentor'\n";
			die "Sorry, you sound like a spam bot - go away. ($req->{comment})" if !$SPAM_OVERRIDE;
		}
		
		
		#die "x";
		
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
		
		my $user = AppCore::Common->context->user;
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
		
		my $comment = Boards::Post->create({
			boardid			=> $board,
			top_commentid		=> $post,
			parent_commentid	=> $req->{parent_commentid},
			poster_name		=> $req->{poster_name},
			poster_email		=> $req->{poster_email},
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
		
		my $user = AppCore::Common->context->user;
		$user = 0 if !$user || !$user->id;
		my $ref = Boards::Post::Like->insert({
			postid	=> $post->id,
			userid	=> $user,
			name	=> $user ? $user->display : '',
			email	=> $user ? $user->email : '',
			photo	=> $user ? $user->photo : '',
		});
		
		#print STDERR "post_like(): New like lineid $ref\n";
			 
		return $post->top_commentid && $post->top_commentid->id ? 'comment' : 'post';
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
		
		# The new_post tmpl names the visible comment field 'age' inorder to confuse spammers. The field named 'comment' is hidden,
		# the logic being that if something *is* in the comment field, then its spam. 
		
		## TODO ## Add bottrick field filtering
# 		# Comment is now hidden, 20090716 JB
# 		# If it has data, then its probably spam. The visible comment field is named "age"
# 		if($req->{comment} && !$SPAM_OVERRIDE)
# 		{
# 			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$req->{comment}', sending to Wikipedia/Spam_(electronic)\n";
# 			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
# 		}
# 		
# 		# Now copy the data over to the proper field so I dont have to patch all the code below
# 		$req->{comment} = $req->{age};

		## TODO ## Add empty text filtering
# 		if(!$req->{comment} || length($req->{comment}) < 5)
# 		{
# 			return PHC::Web::Skin->instance->error("Empty Comment!","You must enter *something* to comment! [2]");
#		}

		## TODO ## Add banned word filtering to post_edit_save()
		
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
}

1;
