use strict;

package PHC::Missions;
{
	# Cheating a bit...
	use base 'AppCore::DBI';
	
	our @PriKeyAttrs = (
		'extra'	=> 'auto_increment',
		'type'	=> 'int(11)',
		'key'	=> 'PRI',
		readonly=> 1,
		auto	=> 1,
	);
	
	__PACKAGE__->meta(
	{
		@Boards::DbSetup::DbConfig,
		table	=> AppCore::Config->get("PHC_MISSIONS") || 'missions',
		
		schema	=> 
		[
			{ field => 'missionid',			type => 'int', @PriKeyAttrs },
			{ field	=> 'boardid',			type => 'int',	linked => 'Boards::Board' },
			{ field	=> 'missionary_userid',		type => 'int',	linked => 'AppCore::User' },
			{ field	=> 'description',		type => 'text' },
			{ field => 'city',			type => 'varchar(255)' },
			{ field	=> 'country',			type => 'varchar(255)' },
			{ field	=> 'mission_name',		type => 'varchar(255)' },
			{ field	=> 'family_name',		type => 'varchar(255)' },
			{ field	=> 'short_tagline',		type => 'varchar(255)' },
			{ field	=> 'location_title',		type => 'varchar(255)' },
			{ field => 'photo_url',			type => 'varchar(255)' },
			{ field	=> 'lat',			type => 'float' },
			{ field	=> 'lng',			type => 'float' },
			{ field => 'deleted',			type => 'int' },
		],	
	});
}

package ThemePHC::Missions;
{
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	
	# This 'Boards' subclass actually is a rather involved subclass. As may know, Boards
	# functions something like this: 
	# [List of Groups (Board::Groups)] ->
	#	[Each Group has a Collection of Boards (Boards::Board)] -> 
	#		[Each Board has Collection of Posts (Boards::Post)] -> 
	#			[Posts have Comments (Boards::Post with top_commentid set)]
	# 
	# What the 'Missions' module does is have a statically-set Boards::Group that it keeps all its data inside.
	# So we have one group, titled 'Missions, and each missionary is represented by a 'Boards::Booard' inside
	# that group. Individual updates/posts from that missionary appear as Boards::Posts in that 'Boards::Board'
	# for that missionary. 
	#
	# Additionally, we have a 'decorator' class called PHC::Missions (defined above) that holds a number of
	# extended attributes. This PHC::Missions class directly corresponds to a Boards::Board object (see
	# PHC::Missions 'boardid' column). 
	#
	# We use a variety of hooks to hook into the 'Board' management routines such as editing the 
	# board (to edit the missionary name/location/photo), and to apply permission restructions.
	#
	# Posting updates in the individual boards need no hooks except one general hook to apply 
	# security permissions. Everything else is handled by the superclass (including commenting functionality.)
	#
	
	use Content::Page;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Missions Database','PHC Missions page, map, etc',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	use DateTime;
	use AppCore::Common;
	use JSON qw/to_json/;
	
	my $MGR_ACL = [qw/MissionsManager/];
	
	my $BOARD_FOLDER = 'missions';
	
	my $SUBJECT_LENGTH = 50;
	
	my $CHANNEL_GROUP = Boards::Group->find_or_create(title=>'Missions');
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			PHC::Missions
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config(
		{
			short_noun	=> 'Missions',
			long_noun	=> 'Missions',
			
			main_tmpl	=> 'missions/main.tmpl',
			edit_forum_tmpl	=> 'missions/edit_forum.tmpl',
			list_tmpl	=> 'missions/list.tmpl',
			post_tmpl	=> 'missions/post.tmpl',
			
			admin_acl	=> [qw/MissionsManager Admin-WebBoards Pastor/],
			
			#notification_methods => [qw/notify_via_email notify_via_facebook notify_via_talk/]
			
			#new_post_tmpl	=> 'pages/missions/new_post.tmpl',
			#post_tmpl	=> 'pages/missions/post.tmpl',
			#post_reply_tmpl	=> 'pages/boards/post_reply.tmpl',
			
			
		});
		
		return $self;
	};
	
# 	sub notify_via_talk
# 	{
# # 		my $self = shift;
# # 		my $post = shift;
# 		
# 		my $self = shift;
# 		my $action = shift;
# 		my $post = shift;
# 		my $args = shift;
# 		
# 		if($action eq 'new_post')
# 		{
# 			my $folder = $post->folder_name;
# 			my $server = AppCore::Config->get('WEBSITE_SERVER');
# 			my $post_url = "${server}/serve/outreach/".$post->boardid->folder_name."/$folder";
# 			
# 			my $data = {
# 				poster_name	=> 'PHC Website',
# 				poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
# 				poster_email	=> 'josiahbryan@gmail.com',
# 				comment		=> "A new update, \"".$post->subject."\" has been added to the missions page for ".$post->boardid->title.". Read it at: $post_url",
# 				subject		=> "New Missions Update: '".$post->subject."' in ".$post->boardid->title, 
# 			};
# 			
# 			my $talk_board_controller = AppCore::Web::Module->bootstrap('ThemePHC::BoardsTalk');
# 			my $talk_board = Boards::Board->retrieve(1); # id 1 is the prayer/praise/talk board
# 			
# 			my $talk_post = $talk_board_controller->create_new_thread($talk_board,$data);
# 			
# 			# Add extra data internally
# 			$talk_post->data->set('blog_postid',$post->id);
# 			$talk_post->data->set('post_url',$post_url);
# 			$talk_post->data->set('title',$post->subject);
# 			$talk_post->data->set('mission',$post->boardid->title);
# 			$talk_post->data->update;
# 			$talk_post->update;
# 			$talk_post->{_orig} = $post;
# 			
# 			# Note: We call send_notifcations() on $self so it will call our facebook_notify_hook()
# 			#       to reformat the FB story args the way we want them before uploading instead 
# 			#       of using the default story format.
# 			#     - We 'really_upload' so we can use $self (because we want to call our facebook_notify_hook())
# 			#     - Give the $talk_board in the args because the FB notification routine needs the
# 			#       FB wall ID and sync info from the board - and its not set on the Pastor's Blog board
# 			my @errors = $self->send_notifications('new_post',$talk_post,{really_upload=>1, board=>$talk_board}); # Force the FB method to upload now rather than wait for the poller crontab script
# 			if(@errors)
# 			{
# 				print STDERR "Error sending notifications of new blog post $post: \n\t".join("\n\t",@errors)."\n";
# 			}
# 			
# 			return 1;
# 		}
# 		
# 		$! = 'Notify via Talk - Action \''.$action.'\' Not Handled';
# 		return 0;
# 			
# 	}
# 	
# 	sub facebook_notify_hook
# 	{
# 		my $self = shift;
# 		my $post = shift;
# 		my $form = shift;
# 		my $args = shift;
# 		
# 		# Create the body of the FB post
# 		my $post_url = $post->data->get('post_url');
# 		
# 		$form->{message} = $post->text; 
# 		#"New video from PHC: ".$post->data->get('description').". Watch it now at ".LWP::Simple::get("http://tinyurl.com/api-create.php?url=${phc_video_url}");
# 		 
# 		# Set the URL for the link attachment
# 		$form->{link} = $post_url;
# 		
# 		#my $image = $self->video_thumbnail($post);
# 		
# 		#my $pastor_user = AppCore::User->by_field(email => 'pastor@mypleasanthillchurch.org');
# 		
# 		my $orig_post = $post->{_orig};
# 		my $quote;
# 		if(!$orig_post)
# 		{
# 			$quote = "Read the full post at ".$post_url;
# 		}
# 		else
# 		{
# 			our $SHORT_TEXT_LENGTH = 60;
# 			my $short_len = AppCore::Config->get("BOARDS_SHORT_TEXT_LENGTH")     || $SHORT_TEXT_LENGTH;
# 			my $short = AppCore::Web::Common->html2text($orig_post->text);
# 			
# 			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
# 			
# 			$quote = "\"".
# 				 substr($short,0,$short_len) . "\"" .
# 				(length($short) > $short_len ? '...' : '');
# 		}
# 		
# 		my $image = 'http://cdn1.mypleasanthillchurch.org/appcore/mods/User/user_photos/user68813c307218b849d02d2595c96e51e7.jpg'; # Pastors photo
# 		
# 		# Finish setting link attachment attributes for the FB post
# 		$form->{picture}	= $image; # ? $image : 'https://graph.facebook.com/180929095286122/picture';
# 		$form->{name}		= $post->data->get('title');
# 		$form->{caption}	= "in ".$post->data->get('mission');
# 		$form->{description}	= $quote; 
# 		#$post->data->get('description');
# 		
# 		# Update original post with attachment data
# 		my $d = $post->data;
# 		$d->set('has_attach',1);
# 		$d->set('name', $form->{name});
# 		$d->set('caption', $form->{caption});
# 		$d->set('description', $form->{description});
# 		$d->set('picture', $form->{picture});
# 		$d->update;
# 		$post->post_class('link');
# 		$post->update;
# 		
# 		# Replace the default Boards FB action with a link to the video post
# 		$form->{actions} = qq|{"name": "View at PHC's Site", "link": "$post_url"}|;
# 		
# 		# We're working with a hashref here, so no need to return anything, but we will anyway for good practice
# 		return $form;
# 	}
	
# 	# Overrides AppCore::Web::Boards::email_new_post_comment()
# 	sub email_new_post_comments
# 	{
# 		return;
# 		
# 		my $class = shift;
# 		my $comment = shift;
# 		my $comment_url = shift;
# 		
# 		$comment_url =~ s/\/boards\//\/ask_pastor\//g;
# 		
# 		my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':
# 
#     }.AppCore::Web::Common::html2text($comment->text).qq{
# 
# Here's a link to that page: 
#     http://mypleasanthillchurch.org${comment_url}
#     
# Cheers!};
# 		
# 		AppCore::Web::Common->reset_was_emailed;
# 		
# 		AppCore::Web::Common->send_email(['jbryan@productiveconcepts.com'],"[PHC Missions] New Comment on: ".$comment->top_commentid->subject,$email_body);
# 		AppCore::Web::Common->send_email([$comment->parent_commentid->poster_email],
# 			"[PHC Missions] New Comment on: ".$comment->top_commentid->subject,$email_body)
# 				if $comment->parent_commentid && $comment->parent_commentid->id && $comment->parent_commentid->poster_email
# 				&& !AppCore::Web::Common->was_emailed($comment->parent_commentid->poster_email);
# 		AppCore::Web::Common->send_email([$comment->top_commentid->poster_email],
# 			"[PHC Missions] New Comment on: ".$comment->top_commentid->subject,$email_body)
# 				if $comment->top_commentid && $comment->top_commentid->id && $comment->top_commentid->poster_email 
# 				&& !AppCore::Web::Common->was_emailed($comment->top_commentid->poster_email);
# 		
# 		AppCore::Web::Common->reset_was_emailed;
# 		
# 		# A bit of a hack here. The function in AppCore::Web::Boards that calls us normally does
# 		# its own redirect - but I want to hijack the redirect here for myself so I cheat by using the 
# 		# singleton methods on AppCore::Web::Skin to get the AppCore::Web::Result object on which to do the redirect.
# 		#AppCore::Web::Common::redirect($AppCore::Web::Config::DISPATCHER_URL_PREFIX."/ask_pastor#p".$comment->top_commentid);
# 	}
	
# 	# Overrides AppCore::Web::Boards::email_new_post()
# 	sub email_new_post
# 	{
# 		return;
# 		
# 		my $class = shift;
# 		my $post = shift;
# 		my $section_name = shift;
# 		my $folder_name = shift;
# 		
# 		my $fake_it = $post->fake_folder_name;
# 		my $board = $post->boardid;
# 		
# 		my $email_body = qq{A new item was added by }.$post->poster_name." in ".$board->title.qq{:
# 
#     }.AppCore::Web::Common::html2text($post->text).qq{
# 
# Here's a link to that page: 
#     http://mypleasanthillchurch.org$ENV{SCRIPT_NAME}/$section_name/$folder_name
#     
# Cheers!};
# 			#
# 			#
# 		AppCore::Web::Common->send_email(['jbryan@productiveconcepts.com'],"[PHC Missions] New Item Added: ".$post->subject,$email_body);
# 	}
# 	
	
	sub board_page
	{
		my $class = shift;
		my ($req,$r,$board) = @_;
		
		my $sub_page = $req->next_path;
		if($sub_page eq 'new' || $sub_page eq 'post')
		{
			my $can_admin = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($MGR_ACL);
			return $r->error("Not Allowed","Sorry, you're not allowed to post in here.") if !$can_admin;
		}
		## XXX TODO
		#elsif(!$sub_page)
		#{
		#}
		
		return $class->SUPER::board_page($req,$r,$board);
	}
	
	sub new_post_hook
	{
		my $class = shift;
		my $tmpl = shift;
		#die "new post hook";
		my $can_epa = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl([qw/Pastor/]);
		$tmpl->param(can_epa=>$can_epa);
		
		$tmpl->param(has_alt_postas => $can_epa);
		if($can_epa)
		{
			$tmpl->param(alt_postas_name  => $class->{current_missionary} ? $class->{current_missionary}->mission_name : 'Pleasant Hill Church');
			$tmpl->param(alt_postas_email => 'webmaster@mypleasanthillchurch.org');
			$tmpl->param(alt_postas_photo => '/appcore/mods/User/user_photos/fbb55eae25485996cd31b362d9296591f6.jpg');
		}
		
	}
	
	sub forum_list_hook
	{
		my $class = shift;
		my $b = shift;
		
		my $short_len = 255;
		$b->{short_text} = AppCore::Web::Common->html2text($b->{text});
		$b->{short_text} = substr($b->{short_text},0,$short_len) . (length($b->{short_text}) > $short_len ? "... (<a href='$b->{bin}/$b->{pageid}/$b->{folder_name}/$b->{fake_folder_name}'>Read Full Update</a>)" : '');
	}
	
	sub forum_page_hook
	{
		my $class = shift;
		my ($hash,$board) = @_;
		
		my $m = PHC::Missions->by_field(boardid=>$board);
		$class->{current_missionary} = $m;
		
		AppCore::Web::Common::error(500,"You've got a valid WebBoard ID ($board) but no phc.missions row matches that boarid") if !$m || !$m->id;
		
		$hash->{'m_'.$_} = $m->get($_) foreach $m->columns;
		$hash->{m_display_name} = $class->create_folder_name($m);
		
		$hash->{country_us} = 1 if lc $m->country eq 'united states';
	}
	
	# To extract create time info
	use Image::ExifTool ':Public';
	
	sub board_settings_save_hook
	{
		my $class = shift;
		my ($board,$args) = @_;
		
		my $m;
		if(!$args->{boardid}) # this was a "new" request
		{
			$m = PHC::Missions->create({boardid=>$board});
		}
		else
		{
			$m = PHC::Missions->by_field(boardid=>$board);
		}
		
		
		foreach my $key (qw/city country mission_name family_name description/)
		{
			$m->set($key,$args->{$key}) if $m->get($key) ne $args->{$key};
		}
		
		
		my $tmp;
		$board->groupid($CHANNEL_GROUP) 	if $board->groupid 		ne $CHANNEL_GROUP;
		$board->section_name($BOARD_FOLDER) 	if $board->section_name 	ne $BOARD_FOLDER;
		
		$tmp = $class->to_fake_folder_name($class->create_folder_name($m));
		$board->folder_name($tmp)		if $board->folder_name 		ne $tmp;
		
		$tmp = $class->create_folder_title($m);
		$board->title($tmp)			if $board->title 		ne $tmp;
		
		$tmp = $class->create_tagline($m);
		$board->tagline($tmp) 			if $board->tagline		ne $tmp;
		
		$tmp = $class->create_description($m);
		$board->description($tmp)		if $board->description		ne $tmp;
		
		$board->update if $board->is_changed;
		
		
		my $filename = $args->{upload};
		#AppCore::Web::Skin->error("No Filename Given","You must specify a file to upload.")if !$filename;
		if($filename)
		{
			$filename =~ s/^(.*[\/\\])(.*)$/$2/g;
			my $orig_folder = $1;
			my ($ext) = ($filename=~/\.(\w{1,})$/);
			
			#my $thumbnail_filename = "photo".$m->id."-small.$ext";
			my $written_filename = "photo".$m->id.".$ext";
			my $www_path = "missionary_photos";
			my $file_path = AppCore::Config->get("WWW_DOC_ROOT").AppCore::Config->get("WWW_ROOT")."/$www_path";
			
			my $abs = "$file_path/$written_filename";
			
			print STDERR "Uploading [$filename] to [$abs]\n";
			
			my $fh = main::upload('upload');
			open UPLOADFILE, ">$abs" || die "Unable to open $abs for writing: $!";
			binmode UPLOADFILE;
			
			while ( <$fh> )
			{
				print UPLOADFILE $_;
			}
			
			close(UPLOADFILE);
			
			$m->photo_url("/$www_path/$written_filename");
			#$class->fork_system_call('convert',$abs,'-resize',$THUMB_SIZE,"$file_path/$thumbnail_filename");
		}
		
		
		if(!$args->{lat} || !$args->{lng})
		{
			use Geo::Coder::Yahoo;
			my $geocoder = Geo::Coder::Yahoo->new(appid => 'zMyYxHvV34FDIRnu_drm6uKwW4_FMdBikSS14qncsxJMd..cReaCAW1f_rAUH0tbMmc-' );
			my $location = $geocoder->geocode( location => "$args->{city}, $args->{country}" );
			my ($lat,$lng);
			for ( @{$location} )
			{
				my %hash = %{$_};
				($lat,$lng) = ($hash{latitude},$hash{longitude});
			} 

			$args->{lat} = $lat;
			$args->{lng} = $lng;
		}
		
		$m->lat($args->{lat})	if $m->lat != $args->{lat};
		$m->lng($args->{lng})	if $m->lng != $args->{lng};
		
		
		$m->update if $m->is_changed;
		
		AppCore::Web::Common::redirect($AppCore::Web::Config::DISPATCHER_URL_PREFIX.'/'.$BOARD_FOLDER.'/'.$board->folder_name); 
	}
	
	sub board_settings_edit_hook
	{
		my $class = shift;
		my ($board,$tmpl) = @_;
		
		my $m = PHC::Missions->by_field(boardid=>$board);
				
		AppCore::Web::Skin->instance->error(500,"You've got a valid WebBoard ID ($board) but no phc.missions row matches that boarid") if !$m || !$m->id;

		$tmpl->param('m_'.$_ => $m->get($_)) foreach $m->columns;
		$tmpl->param(m_display_name => $class->create_folder_name($m));

		$tmpl->param(country_us => 1) if lc $m->country eq 'united states';
	}
	
	sub board_settings_new_hook
	{
		my $class = shift;
		my ($tmpl) = @_;
	}
	
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
		#return $self->dispatch($req, $r);
		return $self->missions_main($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
	our $MissionsListCache = 0;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
		$MissionsListCache = 0;
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__,'load_missions_list');
	
	sub missions_main
	{
		my $self = shift;
		my ($req,$r) = @_;
		
		#my $section_name = $req->next_path;
		
		my $sub_page = $req->next_path;
		
		my $bin = $self->binpath;
		
		my $can_admin = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($MGR_ACL);
			
		# Send the CRUD actions to the superclass, which in turn, will call our various hooks, above, for our logic
		if($sub_page eq 'edit' || $sub_page eq 'new' || $sub_page eq  'post')
		{
			$self->SUPER::main_page(@_);
		}
		
		elsif($sub_page eq 'delete')
		{
			AppCore::AuthUtil->require_auth($MGR_ACL);
			
			my $m = PHC::Missions->retrieve($req->{mid});
			return $r->error("Invalid MissionID","Invalid MissionID") if !$m;
			
			$m->deleted(1);
			$m->update;
			
			return $r->redirect($self->binpath);
		}
		elsif($sub_page eq 'feed.xml' || $sub_page eq 'rss')
		{
			my $tmpl = $self->rss_feed('missions');
			$tmpl->param(feed_title => 'Missions');
			$tmpl->param(feed_description => 'Pleasant Hill Church\'s Missions Updates');
		
			$r->content_type('text/xml');
			$r->body($tmpl->output);
			return;
		}
		elsif($sub_page)
		{
			my $board = $self->get_board_from_req($req);
			if(!$board)
			{
				return $r->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
			}
			return $self->board_page($req,$r,$board);
		}
		elsif(!$sub_page)
		{
		
			my $tmpl = $self->get_template('missions/main.tmpl');
			#$tmpl->param(pageid => $section_name);
			#$tmpl->param(board_nav => $self->macro_board_nav());
			
			$tmpl->param(groupid => $CHANNEL_GROUP->id);
			$tmpl->param(can_admin => $can_admin);
			
			# Wont do anything if loaded, otherwise, loads from DB
			$self->load_missions_list; 
			
			$tmpl->param(missions_list => $MissionsListCache->{page_list});
			
			my $map_list = $MissionsListCache->{map_list};
			
			my $bin = $self->binpath;
			foreach my $m (@{$map_list || []})
			{
				$m->{binpath} = $bin;
			}
			
			$tmpl->param(mlist => $map_list);
			$tmpl->param(mlist_json => to_json($map_list));
			
			# TODO
# 			$r->html_header('link' => 
# 			{
# 				rel	=> 'alternate',
# 				title	=> 'Pleasant Hill Church - Missions Updates',
# 				href 	=> 'http://www.mypleasanthillchurch.org'.$bin.'/missions/rss',
# 				type	=> 'application/rss+xml'
# 			});
# 			
			#$r->output($tmpl);
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			
			my $body = $r->body;
			$body =~ s/<div class='verse-tag-me'>((?:.|\n)+?)<\/div>/Boards::TextFilter::TagVerses::replace_block($1)/segi;
			$r->body($body);
			
			return $r;
		}
	}
	
	sub load_missions_list
	{
		my $self = shift;
		if(!$MissionsListCache)
		{
			$self->binpath('/serve/outreach'); # needed for priming cache properly
			
			my @missions = PHC::Missions->search(deleted=>0);
			
			my %country_groups;
			
			#my $bin = $self->binpath;
			
			# Force US to the top and International to the bottom of the list
			my %sort_keys = ('united states' => '0', 'international' => 'zzzzzzzzzzzzz');
			foreach my $x (@missions)
			{
				my $c = lc $x->country;
				
				$country_groups{$c} ||= { country => $x->country, list => [] };
				
				$self->prep_mission_item($x);
				
				#die Dumper $x;
				
				push @{$country_groups{$c}->{list}}, $x;
				
				if(!defined $sort_keys{$c})
				{
					$sort_keys{$c} = $c;
				}
			}
			
			my @country_sort = sort { $sort_keys{$a} cmp $sort_keys{$b} } keys %country_groups;
			my @list = map { $country_groups{$_} } @country_sort;
			
			my @map_list;
			foreach my $m (@missions)
			{
				my $ref = {};
				
				$ref->{$_} = $m->get($_) foreach qw/missionid city country mission_name family_name photo_url lat lng deleted/;
				
				#$ref->{binpath} = $bin;
				$ref->{'board_'.$_} = $m->boardid->get($_) foreach qw/folder_name section_name/;
				$ref->{list_title} = $m->family_name ? $m->family_name : $m->mission_name;
				
				push @map_list, $ref;
			}
			
			$MissionsListCache = 
			{
				page_list => \@list,
				map_list  => \@map_list,
			};
		}
		
		return $MissionsListCache->{page_list};
	}
	
	sub create_folder_title
	{
		my $class = shift;
		my $m = shift;
		
		my @args;
		push @args, $m->country;
		push @args, $m->mission_name;
		push @args, $m->family_name if $m->family_name;
		push @args, $m->city if $m->city;
		
		return join ' - ', @args;
	}
	
	sub create_country_list_title
	{
		my $class = shift;
		my $m = shift;

		my @args;
		push @args, $m->mission_name;
		push @args, $m->family_name if $m->family_name;
		push @args, $m->city if $m->city;

		return join ' - ', @args;
	}
	
	sub create_folder_name
	{
		my $class = shift;
		my $m = shift;
		
		return $m->family_name ? $m->family_name : $m->mission_name;
		
	}
	
	sub create_tagline 
	{
		my $class = shift;
		my $mission = shift;
		my $txt = AppCore::Web::Common::html2text($mission->description);
		return substr($txt,0,255) . (length($txt) > 255 ? '...':'');
	}
	
	sub create_description
	{
		my $class = shift;
		my $m = shift;
		return $m->description;
	}
	
	sub prep_mission_item
	{
		my $class = shift;
		my $m = shift;
		
		my $board = $class->check_webboard($m);
		
		$m->{binpath} = $class->binpath;
		$m->{$_} = $m->get($_) foreach $m->columns;
		$m->{'board_'.$_} = $board->get($_) foreach $board->columns;
		$m->{list_title} = $class->create_country_list_title($m);
	}
	
	sub check_webboard
	{
		my $class = shift;
		my $m = shift;
		my $board = $m->boardid;
		
		if(!$board || !$board->id)
		{
			$board = Boards::Board->create({
				groupid		=> $CHANNEL_GROUP,
				section_name	=> $BOARD_FOLDER,
				folder_name	=> $class->to_folder_name($class->create_folder_name($m)),
				title		=> $class->create_folder_title($m),
				tagline		=> $class->create_tagline($m),
				description	=> $class->create_description($m),
			});

			$m->boardid($board);
			$m->update;

		}	

		else
		{
			my $title = $class->create_folder_title($m);
			my $folder = $class->to_folder_name($class->create_folder_name($m));

			$board->title($title)        if $board->title  ne $title;
			$board->folder_name($folder) if $board->folder_name ne $folder;
			$board->update if $board->is_changed;
		}
		
		return $board;
	}
	
	
}


1;