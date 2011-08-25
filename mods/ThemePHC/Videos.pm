use strict;

# package PHC::Video;
# {
# 	use base 'AppCore::DBI';
# 	
# 	#use ThemePHC::Groups;
# 	
# 	__PACKAGE__->meta(
# 	{
# 		@Boards::DbSetup::DbConfig,
# 		table	=> 'videos',
# 		
# 		schema	=> 
# 		[
# 			{ field => 'videoid',			type => 'int', @AppCore::DBI::PriKeyAttrs },
# 			{ field	=> 'groupid',			type => 'int',	linked => 'PHC::Group' },
# 			{ field	=> 'contact_userid',		type => 'int',	linked => 'AppCore::User' },
# 			{ field => 'contact_name',		type => 'varchar(255)' },
# 			{ field => 'contact_email',		type => 'varchar(255)' },
# 			{ field	=> 'video_text',		type => 'text' },
# 			{ field	=> 'page_details',		type => 'text' },
# 			{ field => 'is_weekly',			type => 'int(1)'},
# 			{ field	=> 'datetime',			type => 'datetime'},
# 			{ field	=> 'end_time',			type => 'time' },
# 			{ field => 'show_endtime',		type => 'int(1)', null=>0, default=>0 },
# 			{ field => 'weekday',			type => 'int'},
# 			{ field => 'at_phc',			type => 'int(1)'},
# 			{ field => 'location',			type => 'text'},
# 			{ field => 'location_map_link',		type => 'text'},
# 			{ field	=> 'postid',			type => 'int',	linked => 'Boards::Post' },
# 			{ field => 'fake_folder_override',	type => 'int' },
# 			{ field => 'deleted',			type => 'int' },
# 		],	
# 	});
# }

package Boards::VideoProvider::VimeoPHC;
{
	use Boards;
	use base 'Boards::VideoProvider::Vimeo';
	__PACKAGE__->register(
		{	
			name		=> 'PHC Video Page',
			url_regex	=> qr/\#phc-vimeo-vid(\d+)/,
		},
		# Copy missing config keys from the config for this video provider package
		'Boards::VideoProvider::Vimeo'
	); 
};

package ThemePHC::Videos;
{
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	use Content::Page;
	
	use Boards::Data;
	
	use JSON qw/decode_json/;
	use LWP::Simple qw/get/;
	
	# This 'Boards' subclass is rather simple. As may know, Boards functions something like this:
	# 
	# [List of Groups (Board::Groups)] ->
	#	[Each Group has a Collection of Boards (Boards::Board)] -> 
	#		[Each Board has Collection of Posts (Boards::Post)] -> 
	#			[Posts have Comments (Boards::Post with top_commentid set)]
	#
	# This subclass just uses a single 'Boards::Board' to keep all its videos within as 
	# specially crafted Boards::Posts (each PHC::Video (above) corresponds to a single Boards::Post).
	#
	# We maintain a decorator table outside of Boards::Post instead of using the user-data
	# functions in Boards::Post::data() because we want to be able to use SQL to query for
	# date ranges and other arbitrary queries for videos. Since the 'data' field in Boards::Posts
	# is stored as a JSON string in a 'text' field, queries against that are very risky in terms
	# of reliability. It's much cleaner to just query against specific columns in PHC::Videos,
	# then do join in SQL or even just in perl to get the corresponding Boards::Post object.
	#
	# Boards::Posts aren't strictly necessary - we could have written this Videos module without 
	# subclassing Boards at all. However, it does provide us with the commenting functionality
	# and takes care of spam filtering. Additionally, building on an existing module just keeps
	# us from having to worry about *all* the details. Additionally, by maintining appropriatly
	# rendered Boards::Post objects, we get 'Activity Log' and 'Search' support for free. 
	#
	# Once we do this module "right", we'll use a similar subclass arragement (with misc changes)
	# for the Pastors Blog, Ask Pastor, Video, and Audio recording modules.
	#
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Videos Database','PHC Videos',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	use Data::Dumper;
	use DateTime;
	use AppCore::Common;
	use JSON qw/to_json/;
	
	my $MGR_ACL = [qw/VideosManager/];
	
	my $BOARD_FOLDER = 'videos';
	
	my $SUBJECT_LENGTH = 50;
	
	our $VIDEOS_BOARD = Boards::Board->find_or_create(title=>'Videos', folder_name=>'videos');
	
	sub apply_mysql_schema
	{
		my $self = shift;
# 		my @db_objects = qw{
# 			PHC::Video
# 		};
# 		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config(
		{
			short_noun	=> 'Videos',
			long_noun	=> 'Videos',
			
			# TODO figure out which templates we want to override
# 			main_tmpl	=> 'videos/main.tmpl',
# 			new_post_tmpl	=> 'videos/new_post.tmpl',
# 			list_tmpl	=> 'videos/list.tmpl',
# 			post_tmpl	=> 'videos/post.tmpl',
			
			
# 			post_reply_tmpl	=> 'boards/post_reply.tmpl',
# 			edit_forum_tmpl	=> 'boards/edit_forum.tmpl',
			
			admin_acl	=> [qw/VideosManager Admin-WebBoards Pastor/],
			
			#new_post_tmpl	=> 'pages/videos/new_post.tmpl',
			#post_tmpl	=> 'pages/videos/post.tmpl',
			#post_reply_tmpl	=> 'pages/boards/post_reply.tmpl',
			
			
		});
		
		return $self;
	};
		
	# Board page is everything we do - it's the listing of videos - the main page
	# We'll also provide an "alternate view" - a calendar page
	
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
		elsif(!$sub_page || ($sub_page eq 'videos' && !$req->next_path(1)))
		{
			return $class->basic_view($req,$r);
		}
		
		# Not needed now I think...
		#$req->unshift_path('videos') unless $sub_page eq 'videos';
		#die Dumper $req;
		
		return $class->SUPER::board_page($req,$r,$board);
	}
	
	sub new_post_hook
	{
		my $self = shift;
		my $tmpl = shift;
		my $board = shift;
# 		$tmpl->param(video_at_phc => 1);
# 		$tmpl->param(hr_12 => 1);
# 		$tmpl->param(date => (split /\s/, date())[0]);
	}
	
# 	sub load_post 
# 	{
# 		my $class = shift;
# 		my ($post,$section_name,$board_folder_name) = @_;

	sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
	{
		my $self = shift;
		
		my ($post) = @_;
		
		my $rs = $self->SUPER::load_post(@_);
		
		# Apply text changes here
		#$rs->{post_text} = $tmpl->output;
		
# 		my $x = PHC::Video->retrieve($post->data->get('itemid'));
# 		$rs->{type_video} = 1;
# 		$rs->{'video_'.$_} = $x->get($_) foreach $x->columns;
# 		
# 		$post->{item} = $x;
 		$self->prep_video_hash($post);
 		
 		#$rs->{'video_'.$_} = $post->data->get($_) foreach qw/title description url duration/;
 		 
 		$rs->{post_text} = $post->data->get('description'). $self->create_video_links($post->external_url,1);
# 		
# 		foreach my $prep_key (qw/time same_day day_name normal_datestamp timestamp end_time/)
# 		{
# 			$rs->{$prep_key} = $post->{$prep_key};
# 		}
	
		return $rs;
	}
	
	sub load_post_edit_form
	{
		my $class = shift;
		my $post = shift;
		
		my $rs = $class->SUPER::load_post_edit_form($post);
		
# 		my $x = PHC::Video->retrieve($post->data->get('itemid'));
# 		$rs->{type_video} = 1;
# 		$rs->{'video_'.$_} = $x->get($_) foreach $x->columns;
# 		$rs->{'dow'.$x->weekday} = 1;
# 		
# 		my ($date,$time) = split/\s/, $x->datetime;
# 		$rs->{date} = $date;
# 		
# 		my ($hr,$min,$sec) = split/:/, $time;
# 		$rs->{'hr_'.($hr+0)} = 1;
# 		$rs->{min} = $min;
# 		
# 		my ($end_hr,$end_min) = split/:/, $x->end_time;
# 		$rs->{'hr2_'.($end_hr+0)} = 1;
# 		$rs->{end_min} = $end_min;
		
		#die Dumper $rs;
		
		return $rs;
	}
	
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $args = shift;
		
		#my $filename = $args->{upload};
		#PHC::Web::Skin->error("No Filename Given","You must specify a file to upload.")if !$filename;
		
# 		if(!$args->{subject})
# 		{
# 			$args->{subject} = $self->guess_subject($args->{comment});
# 		}
# 		
		#die Dumper ($args);
			
		# TODO implement
		#$self->import_uploaded_image($post,$filename,'upload');
		
		# - Figure out if they're adding a news item or video
		# - add appros object to database
		# - set $post->data->type and $post->data->itemid 
		# - redirect to main page
		
# 		$args->{datetime} = $args->{date}.' '.$args->{hour}.':'.$args->{min}.':00';
# 		$args->{end_time} = $args->{end_hour}.':'.$args->{end_min}.':00';
# 		
# 		$args->{comment} = $args->{datetime}.($args->{show_endtime} ? "-$args->{end_time}":"").' - '.$args->{subject};  
		
		my $post = $self->SUPER::create_new_thread($board,$args);
		
# 		my $ref = {
# 			postid		=> $post->id,
# 			contact_userid	=> AppCore::User->by_field(email => $args->{contact_email}),
# 			video_text	=> $args->{subject},
# 			is_weekly	=> $args->{is_weekly} eq 'yes' ? 1:0,
# 			datetime	=> $args->{datetime},
# 			end_time	=> $args->{end_time},
# 			show_endtime	=> $args->{show_endtime},
# 			weekday		=> $args->{weekday},
# 			page_details	=> $args->{page_details},
# 			contact_email	=> $args->{contact_email},
# 			contact_name	=> $args->{contact_name},
# 			at_phc		=> $args->{at_phc} eq 'yes' ? 1:0,
# 			location	=> $args->{location},
# 			location_map_link => $args->{map_link},
# 		};
		
		#die Dumper $ref, $post, $args;
		
# 		my $x = PHC::Video->create($ref);
# 		
# 		#$post->data->set('type','video'); # TODO is this still needed?
# 		$post->data->set('itemid',$x->id);
# 		$post->data->update;
		
#		print STDERR "Created video $x, postid $post\n";
		return $post;
	}
	
	sub post_edit_save
	{
		my $self = shift;
		my $post = shift;
		my $args = shift;
		
		#die Dumper $args;
		
# 		$args->{datetime} = $args->{date}.' '.$args->{hour}.':'.$args->{min}.':00';
# 		$args->{end_time} = $args->{end_hour}.':'.$args->{end_min}.':00';
# 		
# 		$args->{comment} = $args->{datetime}.($args->{show_endtime} ? "-$args->{end_time}":"").' - '.$args->{subject};
# 		
 		$self->SUPER::post_edit_save($post,$args);
		
# 		my $x = PHC::Video->retrieve($post->data->get('itemid'));
# 		
# 		$x->contact_userid(		AppCore::User->by_field(email => $args->{contact_email}));
# 		$x->contact_email(		$args->{contact_email});
# 		$x->contact_name(		$args->{contact_name});
# 		$x->end_time(			$args->{end_time});
# 		$x->show_endtime(		$args->{show_endtime});
# 		$x->video_text(			$args->{subject});
# 		$x->page_details(		$args->{page_details});
# 		$x->is_weekly(			$args->{is_weekly} eq 'yes' ? 1:0);
# 		$x->fake_folder_override(	$args->{fake_folder_override} eq 'yes' ? 1:0);
# 		$x->datetime(			$args->{datetime});
# 		$x->weekday(			$args->{weekday});
# 		$x->at_phc(			$args->{at_phc} eq 'yes' ? 1:0);
# 		$x->location(			$args->{location});
# 		$x->location_map_link(		$args->{map_link});
# 		
# 		$x->update;
	
		return $post;
		
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
		return $self->videos_main($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
	our $VideosListCache = 0;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing cached data...\n";
		$VideosListCache = 0;
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	
	sub videos_main
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
			$self->board_page($req,$r,$VIDEOS_BOARD);
		}
		
# 		elsif($sub_page eq 'delete')
# 		{
# 			AppCore::AuthUtil->require_auth($MGR_ACL);
# 			
# 			my $m = PHC::Videos->retrieve($req->{mid});
# 			return $r->error("Invalid MissionID","Invalid MissionID") if !$m;
# 			
# 			$m->deleted(1);
# 			$m->update;
# 			
# 			return $r->redirect($self->binpath);
# 		}
		elsif($sub_page eq 'feed.xml' || $sub_page eq 'rss')
		{
			my $tmpl = $self->rss_feed('videos');
			$tmpl->param(feed_title => 'Videos');
			$tmpl->param(feed_description => 'Pleasant Hill Church\'s Videos');
			
			$r->content_type('text/xml');
			$r->body($tmpl->output);
			return;
		}
		elsif(!$sub_page || $sub_page eq 'raw' || $sub_page eq 'basic')
		{
			return $self->basic_view($req,$r);
		}
		elsif($sub_page)
		{
			# For some reason, tinyurl doesn't include the '#' and following in the encode URL.
			# So, we to a redirect to include the #autoplay on the assumption that it was supposed to be there
			if($ENV{HTTP_REFERER} =~ /tinyurl/)
			{
				my $url = AppCore::Web::Common::get_full_url();
				if($url !~ /ap=1/) # Prevent endless redirect loops
				{
					$url .= $url =~ /\?/ ? '&ap=1' : '?ap=1';
					return $r->redirect($url.'#autoplay');
				}
			}
			return $self->board_page($req,$r,$VIDEOS_BOARD);
		}
	}
	
	sub load_video_list
	{
		my $self = shift;
		if(!$VideosListCache)
		{
# 			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($MGR_ACL);
# 			my $sql = "datetime >= NOW() OR is_weekly = 1";
# 			#print STDERR "SQL=$sql\n";
# 			my @videos = PHC::Video->retrieve_from_sql($sql);
# 			
# 			my @weekly;
# 			my @dated;
# 			
# 			#my $cur_dow = get_dow(EAS::Common::date());
# 			foreach my $item (@videos)
# 			{
# 				my $video = $self->merge_item_to_post($item,$can_admin);
# 				next if !$video || $video->{deleted};
# 				
# 				$self->prep_video_hash($video);
# 				
# 				if($video->{item}->is_weekly)
# 				{
# 					push @weekly, $video;
# 				}
# 				else
# 				{
# 					push @dated, $video;
# 				}
# 			}
# 			
# 			@weekly = sort {$a->{item_weekday}  cmp $b->{item_weekday}  } @weekly;
# 			@dated  = sort {$a->{item_datetime} cmp $b->{item_datetime} } @dated;
# 			
# 			# Group by week day
# 			my $out_weekly = $self->process_weekly_video_list(\@weekly);
			
			$VideosListCache = {
# 				weekly	=> $out_weekly,
# 				dated	=> \@dated,
			};
		}
		
		return $VideosListCache;
			 
	}
	
	sub basic_view
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $board = $VIDEOS_BOARD;
		
		#my $tmpl = $self->get_template($self->config->{list_tmpl} || 'videos/list.tmpl');
		my $tmpl = $self->get_template('videos/list.tmpl');
		
		$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($MGR_ACL);
		$tmpl->param(can_admin=>$can_admin);
		$tmpl->param(videos_page => 1);
		
		my $output = $self->load_post_list($board, {idx=>$req->idx, len=>$req->len || 25 });
		
		foreach my $post (@{$output->{posts}})
		{
			$post->{video_attach} = $self->create_video_links($post->{text},1);
		}
		
		#$tmpl->param(board_nav => $controller->macro_board_nav());
		#$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
		#$tmpl->param(user_email_md5 => md5_hex($user->email)) if $user && $user->id;
		#$tmpl->param(boards_indent_multiplier => $INDENT_MULTIPLIER);
		
		my $tmpl_incs = $self->config->{tmpl_incs} || {};
		#use Data::Dumper;
		#die Dumper $tmpl_incs;
		foreach my $key (keys %$tmpl_incs)
		{
			$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
		}
		
		# Since a theme has the option to inline a new post form in the post template,
		# provide the controller a method to hook into the template variables from here as well
		$self->new_post_hook($tmpl,$board);
		
		$tmpl->param($_ => $output->{$_}) foreach keys %$output;
		
		$self->apply_video_providers($tmpl);
		
		my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
		return $r;
	}
	
	sub sync_from_vimeo
	{
		my $self = shift;
		my $vimeo_url = 'http://vimeo.com/api/v2/user5527613/videos.json';
		
		my $json = LWP::Simple::get($vimeo_url);
		my $list = decode_json($json) || [];
		
		my $user = AppCore::User->retrieve(1); # Josiah
		
		$self->binpath(AppCore::Config->get('WEBSITE_SERVER') . "/learn/videos");
		
		foreach my $vdat (@$list)
		{
			#print STDERR "Checking post ".$vdat->{id}." - ".$vdat->{title}."\n";
			my $post_text = "<span class=title>$vdat->{title}</span><span class=filler>: </span><span class=url>$vdat->{url}</span><span class=filler> - </span><span class=description>$vdat->{description}</span>";
			my $post = Boards::Post->by_field(external_source => 'Vimeo', external_id => $vdat->{id}, deleted => 0);
			if(!$post)
			{
				#die "Missed video $vdat->{id}";
				
				# Create a set of arguments for create_new_thread()
				my $data = {
					poster_name	=> 'PHC AV Team',
					poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
					poster_email	=> 'josiahbryan@gmail.com',
					comment		=> $post_text,
					subject		=> $vdat->{title}, 
				};
				
				# Use Boards to create a new thread
				$post = $self->create_new_thread($VIDEOS_BOARD, $data, $user);
				
				$post->timestamp($vdat->{upload_date});
				$post->updated_time($vdat->{upload_date});
				
				# Flag it as from Vimeo and store the Vimeo Video ID for future reference
				$post->external_source('Vimeo');
				$post->external_id($vdat->{id});
				$post->external_url($vdat->{url});
				
				$post->post_class('video');
				
				$post->data->set($_, $vdat->{$_}) foreach qw/title description url duration/;
				
				my $video_url = $self->binpath . "/" . $post->folder_name . '#phc-vimeo-vid'.$vdat->{id};
				$post->data->set('phc_video_url', $video_url);
				
				$post->data->update;
				
				$post->update;
			
				#$post_is_new = 1;
				
				
				my $talk_board_controller = AppCore::Web::Module->bootstrap('ThemePHC::BoardsTalk');
				my $talk_board = Boards::Board->retrieve(1); # id 1 is the prayer/praise/talk board
				my $talk_args = $data;
				$data->{comment} = $vdat->{description}.'. Watch it now at '.$video_url; #$vdat->{url}; 
				
				my $talk_post = $talk_board_controller->create_new_thread($talk_board,$talk_args);
				
				# Note: We call send_notifcations() on $self so it will call our facebook_notify_hook()
				#       to reformat the FB story args the way we want them before uploading instead 
				#       of using the default story format.
				#     - We also send notifications for our video $post, NOT the $talk_post, since 
				#       the video $post has the extra data attributes we can use.
				#     - Give the $talk_board in the args because the FB notification routine needs the
				#       FB wall ID and sync info from the board - and its not set on the Video board
				my @errors = $self->send_notifications('new_post',$post,{really_upload=>1, board=>$talk_board}); # Force the FB method to upload now rather than wait for the poller crontab script
				if(@errors)
				{
					print STDERR "Error sending notifications of new video post $post: \n\t".join("\n\t",@errors)."\n";
				}
				
				
				# Reset external_id on this post because the FB upload script overwrites our ID
				$post->external_id($vdat->{id});
				$post->update;
				
				print "Created post from Vimeo - # $post - '".$post->subject."' - $video_url (talk post $talk_post)\n";
				
				#die "Test done";
			}
			else
			{
				my $changed = 0;
				foreach my $key (qw/title description url duration/)
				{
					if($vdat->{$_} ne $post->data->get($_))
					{
						$post->data->set($_, $vdat->{$_});
						$changed = 1; 
					}
				}
				
				if($changed)
				{
					$post->text($post_text);
					$post->subject($vdat->{title});
					$post->update;
					
					my $url = AppCore::Config->get('WEBSITE_SERVER') . "/learn/videos/" . $post->folder_name;
					print "Updated Video Post - # $post - '".$post->subject."' - $url\n";
				}
				
# 				$post->timestamp($vdat->{upload_date});
# 				$post->updated_time($vdat->{upload_date});
# 				$post->update;
				
				
			}
		}
# 
# 
# {
# "id":25717193,
# "title":"PHC Sunday Morning Sermon - \"Confidence in Prayer\" - 2011-06-26",
# "description":"Pastor Bryan teaches us how we can have \"Confidence in Prayer\" at Pleasant Hill Church, June 26th, 2011",
# "url":"http:\/\/vimeo.com\/25717193",
# "upload_date":"2011-06-28 10:44:27",
# "mobile_url":"http:\/\/vimeo.com\/m\/#\/25717193",
# "thumbnail_small":"http:\/\/b.vimeocdn.com\/ts\/169\/503\/169503892_100.jpg",
# "thumbnail_medium":"http:\/\/b.vimeocdn.com\/ts\/169\/503\/169503892_200.jpg",
# "thumbnail_large":"http:\/\/b.vimeocdn.com\/ts\/169\/503\/169503892_640.jpg",
# "user_name":"Josiah Bryan",
# "user_url":"http:\/\/vimeo.com\/user5527613",
# "user_portrait_small":"http:\/\/a.vimeocdn.com\/portraits\/defaults\/d.30.jpg",
# "user_portrait_medium":"http:\/\/a.vimeocdn.com\/portraits\/defaults\/d.75.jpg",
# "user_portrait_large":"http:\/\/a.vimeocdn.com\/portraits\/defaults\/d.100.jpg",
# "user_portrait_huge":"http:\/\/a.vimeocdn.com\/portraits\/defaults\/d.300.jpg",
# "stats_number_of_likes":0,
# "stats_number_of_plays":0,
# "stats_number_of_comments":0,
# "duration":2379,
# "width":640,
# "height":480,
# "tags":"",
# "embed_privacy":"anywhere"
# },


		
		
	}
	
# 			my $post_text = "<span class=title>$vdat->{title}</span><span class=filler>: </span><span class=url>$vdat->{url}</span><span class=filler> - </span><span class=description>$vdat->{description}</span>";

# 			my $data = {
# 				poster_name	=> 'PHC AV Team',
# 				poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
# 				poster_email	=> 'josiahbryan@gmail.com',
# 				comment		=> $post_text,
# 				subject		=> $vdat->{title}, 
# 			};
# 			
# 			$post->timestamp($vdat->{upload_date});
# 			$post->updated_time($vdat->{upload_date});
# 			
# 			# Flag it as from Vimeo and store the Vimeo Video ID for future reference
# 			$post->external_source('Vimeo');
# 			$post->external_id($vdat->{id});
# 			$post->external_url($vdat->{url});
# 			
# 			$post->post_class('video');
# 			
# 			$post->data->set($_, $vdat->{$_}) foreach qw/title description url duration/;

# 	my $form = 
# 	{
# 		access_token	=> $fb_access_token,
# 		message		=> $message,
# 		link		=> $abs_url,
# 		picture		=> $photo,
# 		name		=> $post->subject,
# 		caption		=> $action eq 'new_post' ? 
# 			"by ".$post->poster_name." in ".$board->title :
# 			"by ".$post->poster_name." on '".$post->top_commentid->subject."' in ".$board->title,
# 		description	=> $short_text,
# 		actions		=> qq|{"name": "View on the PHC Website", "link": "$abs_url"}|,
# 	};
	
	sub video_thumbnail
	{
		my $self = shift;
		my $post = shift;
		
		if(my $thumb = $post->data->get('thumbnail'))
		{
			return $thumb;
		}
		
		my $image = '';
		my $source = $post->external_source;
		if($source eq 'Vimeo')
		{
			# Craft the metadata URL for vimeo inorder to download the thumnail
			my $id = $post->external_id;
			my $url = "http://vimeo.com/api/v2/video/" . $id . ".json";
			#print STDERR "\tVimeo video - calling $url\n";
			
			# Download and decode metadata
			#print STDERR __PACKAGE__."::facebook_notify_hook: Downloading metadata for video $id from URL $url, got: '$json'\n"; 
			my $json = LWP::Simple::get($url);
			my $data = decode_json($json ? $json : '[]');
			
			# Extract thumbnail URL
			my @list = @{$data || []};
			my $meta = shift @list;
			$image = $meta->{thumbnail_small};
			
			#print STDERR "\t Downloaded image $image\n";
		}
		elsif($source eq 'YouTube')
		{
			my $url = $post->external_url;
			my ($code) = $url =~ /v=([a-zA-Z0-9\-]+)/;
			$image = "http://img.youtube.com/vi/$code/1.jpg";
		}
		else
		{
			warn __PACKAGE__."::video_thumbnail: I don't know how to get thumbnail for a ${source} video - sorry!";
			
			# Default PHC profile photo on FB
			$image = 'https://graph.facebook.com/180929095286122/picture';
		}
		
		$post->data->set('thumbnail', $image);
		$post->data->update;
		$post->update;
		
		return $image;

		
	}
	
	sub facebook_notify_hook
	{
		my $self = shift;
		my $post = shift;
		my $form = shift;
		my $args = shift;
		
		# Create the body of the FB post
		my $phc_video_url = $self->binpath . '/' . $post->folder_name . '#autoplay';
		$form->{message} = "New video from PHC: ".$post->data->get('description').". Watch it now at ".LWP::Simple::get("http://tinyurl.com/api-create.php?url=${phc_video_url}");
		 
		# Set the URL for the link attachment
		$form->{link} = $phc_video_url;
		
		my $image = $self->video_thumbnail($post);
		
		# Finish setting link attachment attributes for the FB post
		$form->{picture}	= $image; # ? $image : 'https://graph.facebook.com/180929095286122/picture';
		$form->{name}		= $post->data->get('title');
		$form->{caption}	= "by Pleasant Hill Church AV Team";
		$form->{description}	= $post->data->get('description');
		
		# Replace the default Boards FB action with a link to the video post
		$form->{actions} = qq|{"name": "View at PHC's Site", "link": "$phc_video_url"}|;
		
		# We're working with a hashref here, so no need to return anything, but we will anyway for good practice
		return $form;
	}
	
# 	sub merge_item_to_post
# 	{
# 		my $self = shift;
# 		my $item = shift;
# 		my $can_admin = shift;
# 		
# 		my $section_name = 'videos';
# 		my $folder_name = 'videos';
# 		
# 		my $post = $item->postid;
# 		if(!$post)
# 		{
# 			print STDERR "Debug: invalid postid for item <$item>\n";
# 			return undef;
# 		}
# 		
# 		#print STDERR "merge_item_to_post: load_post: b: $b, boardid: ".$b->boardid."\n";
# 		my $board = $post->boardid;
# 		#print STDERR "merge_item_to_post: load_post: b: $b, boardid: ".$post->boardid.", ref:(".ref($board).")\n";
# 		
# 		my $b = {};
# 		
# 		my $bin = $self->binpath;
# 		
# 		my $short_len = 60;
# 		
# 		#EAS::Common::print_stack_trace();
# 		$b->{$_} = "".$post->get($_) foreach $post->columns;
# 		$b->{bin} = $bin;
# 		$b->{pageid} = $section_name;
# 		$b->{folder_name} = $folder_name;
# 		$b->{can_admin} = $can_admin;
# 		$b->{text} =~ s/<(\/)?pre.*?>/<$1p>/g;
# 		$b->{text} =~ s/<(\/)?span.*?>//g;
# 		$b->{text} =~ s/<p>&nbsp;<\/p>//gi;
# 		$b->{text} =~ s/(^<p>|<\/p>$)//g ; #unless index(lc $b->{text},'<p>') > 0;z
# 		$b->{short_text} = $b->{text};
# 		$b->{short_text} =~ s/<[^\>]+>//g;
# 		$b->{short_text} = substr($b->{short_text},0,$short_len) . (length($b->{short_text}) > $short_len ? '...' : '');
# 		
# 		$b->{type_video} = 1;  # TODO is this needed?
# 		
# 		my $lc = $post->{last_commentid};
# 		if($lc && $lc->id)
# 		{
# 			$b->{'post_'.$_} = "".$lc->get($_) foreach $lc->columns;
# 			$b->{post_url} = $bin."/$b->{folder_name}#c$lc";
# 		}
# 		
# 		my @keys = keys %$b;
# 		#$b->{'post_'.$_} = $b->{$_} foreach @keys;
# 		#$b->{'board_folder_name'} = $BOARD_FOLDER;
# 		my $post_resultset = $self->SUPER::load_post($post,1); # 1 = dont count view
# 		$b->{$_} = $post_resultset->{$_} foreach keys %$post_resultset;
# 			
# 		$b->{'item_'.$_}  = $item->get($_),"" foreach $item->columns; # TODO which line is needed??
# 		$b->{'video_'.$_} = $item->get($_)."" foreach $item->columns;
# 		$b->{item} = $item;
# 		$b->{post} = $post;
# 		return $b;
# 	}
# 	
	sub human_time 
	{
		my $timestamp = shift;
		$timestamp = '12:00:00' if $timestamp eq '00:00:00';
			
		my ($hr,$min,$sec) = split /:/, $timestamp;
		
		my $ap = 'am';
		if($hr >= 12)
		{
			$hr -= 12;
			$ap = 'pm';
			$hr = 12 if !$hr;
		}
		$hr +=0;
		
		return "$hr:$min$ap";
	}
	
	sub prep_video_hash
	{
		my $self = shift;
		my $video = shift;
		my $cur_dow = shift;
		
# 		my $item = $video->{item};
# 		
# 		my $dow;
# 		if($item->is_weekly)
# 		{
# 			$dow = $item->weekday;
# 			#$dow = get_dow($video->datetime) if !$dow;
# 			#print STDERR "Soft Video: dt=".$video->datetime.", dow=$dow\n";
# 		}
# 		else
# 		{
# 			
# 			$dow = get_dow($item->datetime);
# 			#print STDERR "Hard Video: dt=".$item->datetime.", dow=$dow\n";
# 		}
# 		
# 		my ($datestamp,$timestamp) = split /\s/, $item->datetime;
# 		
# 		$video->{time} = human_time($timestamp);
# 		$video->{end_time} = human_time($item->end_time);
# 		$video->{same_day} = $cur_dow == $dow;
# 		$video->{day_name} = $DOW_NAMES[$dow];
# 		$video->{day_name_short} = $DOW_NAMES_SHORT[$dow];
# 		$video->{text} = ThemePHC::VerseLookup->tag_verses($video->{text});
# 		
# 		my ($year,$mon,$day) = split/-/, $datestamp;
# 		$video->{normal_datestamp} = (0+$mon)."/".(0+$day)."/".substr($year,-2,2);
# 		$video->{timestamp} = $timestamp;
# 		
# 		$video->{month_name} = $MONTH_NAMES[$mon-1];
# 		$video->{month_name_short} = $MONTH_NAMES_SHORT[$mon-1];
# 		
# 		$video->{year} = $year;
# 		$video->{day} = $day;
		
		#return $dow;
	}
	
# 	sub get_dow
# 	{
# 		my $date = shift;
# 		my ($x,$y) = split /\s/, $date;
# 		my ($year,$month,$day) = split/-/, $x;
# 		my $dt = DateTime->new(year=>$year,month=>$month,day=>$day);
# 		return $dt->dow;
# 	}
# 	
# 	sub process_weekly_video_list
# 	{
# 		my $class = shift;
# 		
# 		my $list = shift;
# 		
# 		my @weekly = sort {$a->{item_weekday}  cmp $b->{item_weekday}  } @$list;
# 		
# 		my @out_weekly;
# 		my $last_dow;
# 		my $dow;
# 		foreach my $item (@weekly)
# 		{
# 			if($dow && $dow->{weekday} != $item->{item_weekday})
# 			{
# 				$dow->{list} = [ sort { $a->{item_datetime} cmp $b->{item_datetime} } @{$dow->{list}} ];
# 				push @out_weekly, $dow;
# 				$dow = undef;
# 			}
# 			
# 			if(!$dow)
# 			{
# 				$dow = {list=>[],day_name=>$item->{day_name},weekday=>$item->{item_weekday}};
# 			}
# 			
# 			push @{$dow->{list}}, $item;
# 			
# 		}
# 		
# 		if($dow)
# 		{
# 			$dow->{weekday} = 0 if $dow->{weekday} == 7;
# 			$dow->{list} = [ sort { $a->{item_datetime} cmp $b->{item_datetime} } @{$dow->{list}} ];
# 			push @out_weekly, $dow;
# 			$dow = undef;
# 			
# 		}
# 		
# 		@out_weekly = sort {$a->{weekday}  cmp $b->{weekday}  } @out_weekly;
# 		
# 		return \@out_weekly;
# 	}
	
}


1;