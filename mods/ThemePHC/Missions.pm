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
		table	=> $AppCore::Config::PHC_MISSIONS || 'missions',
		
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
			
			#new_post_tmpl	=> 'pages/missions/new_post.tmpl',
			#post_tmpl	=> 'pages/missions/post.tmpl',
			#post_reply_tmpl	=> 'pages/boards/post_reply.tmpl',
			
			
		});
		
		return $self;
	};
	
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
		my ($req,$r) = @_;
		
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
		
		return $class->SUPER::forum_page($req,$r);
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
			my $file_path = $AppCore::Config::WWW_DOC_ROOT.$AppCore::Config::WWW_ROOT."/$www_path";
			
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
		my $new_binpath = $AppCore::Config::DISPATCHER_URL_PREFIX . $req->page_path; # this should work...
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
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
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
			return $self->board_page($req,$r);
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
			my @missions = PHC::Missions->search(deleted=>0);
			
			my %country_groups;
			
			my $bin = $self->binpath;
			
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
				
				$ref->{binpath} = $bin;
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