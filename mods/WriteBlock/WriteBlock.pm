use strict;

# package WriteBlock::MetaInfo;
# {
# 	# Cheating a bit...
# 	use base 'AppCore::DBI';
# 	
# 	our @PriKeyAttrs = (
# 		'extra'	=> 'auto_increment',
# 		'type'	=> 'int(11)',
# 		'key'	=> 'PRI',
# 		readonly=> 1,
# 		auto	=> 1,
# 	);
# 	
# 	__PACKAGE__->meta(
# 	{
# 		@Boards::DbSetup::DbConfig,
# 		table	=> $AppCore::Config::PHC_MISSIONS || 'missions',
# 		
# 		schema	=> 
# 		[
# 			{ field => 'missionid',			type => 'int', @PriKeyAttrs },
# 			{ field	=> 'boardid',			type => 'int',	linked => 'Boards::Board' },
# 			{ field	=> 'missionary_userid',		type => 'int',	linked => 'AppCore::User' },
# 			{ field	=> 'description',		type => 'text' },
# 			{ field => 'city',			type => 'varchar(255)' },
# 			{ field	=> 'country',			type => 'varchar(255)' },
# 			{ field	=> 'mission_name',		type => 'varchar(255)' },
# 			{ field	=> 'family_name',		type => 'varchar(255)' },
# 			{ field	=> 'short_tagline',		type => 'varchar(255)' },
# 			{ field	=> 'location_title',		type => 'varchar(255)' },
# 			{ field => 'photo_url',			type => 'varchar(255)' },
# 			{ field	=> 'lat',			type => 'float' },
# 			{ field	=> 'lng',			type => 'float' },
# 			{ field => 'deleted',			type => 'int' },
# 		],	
# 	});
# }


package WriteBlock;
# Writing module - write long things
{
	use AppCore::Web::Common;
	use AppCore::Common;
	use AppCore::EmailQueue;
	use Boards;
	
	use base qw/Boards/;
	
	# Setup the Web Module 
	sub DISPATCH_METHOD { 'main_page'}
	
	# Directly callable methods
	__PACKAGE__->WebMethods(qw{});

	# Contains all the data packages we need, such as Boards::Post, etc
	use Boards::Data;
	
	# Register our pagetype
	#__PACKAGE__->register_controller('PHC Talk Board','PHC Prayer/Praise/Talk Page',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	# Register our controller-specific notifications
# 	our $PREF_EMAIL_PRAISE = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Praise" posts');
# 	our $PREF_EMAIL_PRAYER = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Prayer Requests" posts');
# 	our $PREF_EMAIL_TALK   = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Just Talking" posts');
	
	our $BOARD_GROUP = Boards::Group->find_or_create(title=>__PACKAGE__, hidden=>1);
	
	sub output
	{
		my $pkg = shift;
		my $r = shift;
		my $page_obj = shift;
		
		my $tmpl = $pkg->get_template("writeblock.tmpl");
		
		my $blob = (ref $page_obj && $page_obj->isa('HTML::Template')) ? $page_obj->output : $page_obj;
		my @titles = $blob=~/<title>(.*?)<\/title>/g;
		@titles = $blob=~/<h1>(.*?)<\/h1>/g if !@titles;
		#$title = $1 if !$title;
		@titles = grep { !/\$/ } @titles;
		
		my $pgdat = {};
		$pgdat->{page_title}	= shift @titles;
		$pgdat->{page_content}	= $blob;
		
		$tmpl->param($_ => $pgdat->{$_}) foreach keys %$pgdat;
		
		$r->output($tmpl);
		
		return $r;
	}
	
	sub apply_mysql_schema
	{
		my $self = shift;
# 		my @db_objects = qw{
# 			WriteBlock::MetaInfo
# 		};
# 		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
	}
	
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config({
			
# 			new_post_tmpl	=> 'prayer/new_post.tmpl',
# 			tmpl_incs 	=> 
# 			{
# 				newpost	=> 'inc-newpostform-talkpage.tmpl',
# 				postrow => 'inc-postrow-talkpage.tmpl',	
# 			},
		});
		
		return $self;
	};
	
	sub main_page
	{
		#my ($skin,$r,$page,$req,$path) = @_;
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		
		#$r->header('X-Page-Comments-Disabled' => 1);
		
		# Get all 'boards' owned by 'user'
		# Group is our module group
		# Board is a project
		# User is manager
		# Posts are one-per-paragraph
		
		my $sub_page = $req->next_path;
		
		my $bin = $self->binpath;
		
		# New project
		if($sub_page eq 'new')
		{
			# Must be logged in 
			AppCore::AuthUtil->require_auth();
			
			my $tmpl = $self->get_template($self->config->{edit_forum_tmpl} || 'edit_forum.tmpl');
			$tmpl->param(post_url => "$bin/post");
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			
			
			$tmpl->param('group_'.$_ => $BOARD_GROUP->get($_)) foreach $BOARD_GROUP->columns;
			
			$self->board_settings_new_hook($tmpl) if $self->can('board_settings_new_hook');
			
			my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			return $r;
		}
		# Edit project attributes
		elsif($sub_page eq 'edit')
		{
			my $board = Boards::Board->retrieve($req->{boardid});
			$r->error("Invalid BoardID","Invalid BoardID") if !$board;
			
			# Must be logged in 
			AppCore::AuthUtil->require_auth(); 
			 
			# Since they made it here, they are logged in, so we can use the $user object without checking it 
			my $user = AppCore::Common->context->user;
			
			$r->error("Access Denied","You don't own this project, you can't edit it - sorry!") if $board->managerid->id != $user->id;
			
			my $tmpl = $self->get_template($self->config->{edit_forum_tmpl} || 'edit_forum.tmpl');
			$tmpl->param(post_url => "$bin/post");
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			#my $config = $self->config;
			#print STDERR Dumper $config;
			
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('group_'.$_ => $BOARD_GROUP->get($_)) foreach $BOARD_GROUP->columns;
			
			$self->board_settings_edit_hook($board,$tmpl) if $self->can('board_settings_edit_hook');
			
			return WriteBlock->output($r,$tmpl);
		}
		# Save project attributes
		elsif($sub_page eq 'post')
		{
			# Must be logged in 
			AppCore::AuthUtil->require_auth(); 
			 
			# Since they made it here, they are logged in, so we can use the $user object without checking it 
			my $user = AppCore::Common->context->user;
			
			my $board;
			if($req->{boardid})
			{
				$board = Boards::Board->retrieve($req->{boardid});
				
				if($board)
				{
					$r->error("Access Denied","You don't own this project, you can't edit it - sorry!") if $board->managerid->id != $user->id;
				}
			}
			else
			{
				$board = Boards::Board->create({groupid => $req->{groupid},
					#section_name=>$section_name ## TODO Replace this with the pageid!
					managerid => $user,
				});
			}
			
			$self->board_settings_save_hook($board,$req) if $self->can('board_settings_save_hook');
			
			foreach my $key (qw/folder_name title tagline sort_key/)
			{
				$board->set($key, $req->{$key});
			}
			
			$board->controller(__PACKAGE__) if $board->controller ne __PACKAGE__;
			
			
			$board->update;
			
			$r->redirect($bin); 
		}
		# View project
		elsif($sub_page)
		{
			return $self->board_page($req,$r);
		}
		# List projects
		else
		{
			# They can't see a list of the users projects if not logged in
			AppCore::AuthUtil->require_auth(); 
			 
			# Since they made it here, they are logged in, so we can use the $user object without checking it 
			my $user = AppCore::Common->context->user;
			
			
			my $tmpl = $self->get_template('projects_list.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			#my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});;
			$tmpl->param(can_admin=>1); #$can_admin);
		
# 			my @groups = Boards::Group->search(hidden => 0);
# 			@groups = sort {$a->sort_key cmp $b->sort_key} @groups;
			
			my $appcore = $AppCore::Config::WWW_ROOT;
			
# 			foreach my $g (@groups)
# 			{
# 				$g->{$_} = $g->get($_) foreach $g->columns;
# 				$g->{bin} = $bin;
# 				$g->{appcore} = $appcore;
				
				my @boards = Boards::Board->search(groupid=>$BOARD_GROUP,  managerid => $user);
				@boards = sort {$a->sort_key cmp $b->sort_key} @boards;
				foreach my $b (@boards)
				{
					$b->{$_} = $b->get($_) foreach $b->columns;
					$b->{bin} = $bin;
					$b->{appcore} = $appcore;
					$b->{can_admin} = 1; #$can_admin; # TODO fix this for readonly 
					$b->{board_url} = "$bin/$b->{folder_name}";
					
					my $lc = $b->last_commentid;
					if($lc && $lc->id && !$lc->deleted)
					{
						$b->{'post_'.$_} = $lc->get($_) foreach $lc->columns;
						$b->{post_url} = "$bin/$b->{folder_name}/".$lc->top_commentid->folder_name."#c$lc" if $lc->top_commentid;
					}
				}
				
# 				$g->{can_admin} = $can_admin;
# 				$g->{boards} = \@boards;
# 			}
# 			
			$tmpl->param(boards => \@boards);
			$tmpl->param('group_'.$_ => $BOARD_GROUP->get($_)) foreach $BOARD_GROUP->columns;
			
# 			$r->html_header('link' => 
# 			{
# 				rel	=> 'alternate',
# 				title	=> 'Pleasant Hill Church RSS',
# 				href 	=> 'http://www.mypleasanthillchurch.org'.$bin.'/boards/rss',
# 				type	=> 'application/rss+xml'
# 			});
			#my $view = Content::Page::Controller->get_view('sub',$r)->output($tmpl);
			#return $r;
			return WriteBlock->output($r,$tmpl);
		}
	}
	
	sub board_page
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		my $board = shift || undef;
		
		my $folder_name = $req->shift_path;
		
		$req->push_page_path($folder_name);
		
		$board = Boards::Board->by_field(folder_name => $folder_name) if !$board;
		if(!$board)
		{
			return $r->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		# They can't view project if not logged in
		AppCore::AuthUtil->require_auth(); 
			
		# Since they made it here, they are logged in, so we can use the $user object without checking it 
		my $user = AppCore::Common->context->user;
		
		# For now, limit to manager
		return $r->error("Readonly not done yet", "Sorry, you dont own it, and I havn't finished the readonly part yet") if $board->managerid->id != $user->id;
		
		
		my $sub_page = $req->next_path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = $self->binpath;
		
		if($sub_page eq 'post')
		{
			my $post = $self->create_new_thread($board,$req);
			
			$self->send_notifications('new_post',$post);
			#$r->redirect(AppCore::Common->context->http_bin."/$section_name/$folder_name#c$post");
			
			if($req->output_fmt eq 'json')
			{
				my $b = $self->load_post_for_list($post,$board->folder_name);
				
				#use Data::Dumper;
				#print STDERR "Created new postid $post, outputting to JSON, values: ".Dumper($b);
				
				my $json = encode_json($b);
				return $r->output_data("application/json", $json);
			}
			
			return $r->redirect("$bin/$folder_name");
		}
		elsif($sub_page eq 'new')
		{
			my $tmpl = $self->get_template($self->config->{new_post_tmpl} || 'new_post.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			$tmpl->param(post_url => "$bin/$folder_name/post");
			
			#die $self;
			$self->new_post_hook($tmpl,$board);
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('New Post',"$bin/$folder_name/new",0);
			$view->output($tmpl);
			return $r;
		}
		elsif($sub_page eq 'print_list')
		{
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
			
			my $tmpl = $self->get_template($self->config->{print_list_tmpl} || 'print_list.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $self->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $self->config->{long_noun}  || 'Bulletin Boards');
			
			my $tmpl_incs = $self->config->{tmpl_incs} || {};
			foreach my $key (keys %$tmpl_incs)
			{
				$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
			}
			
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
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
			
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
			return $self->post_page($req,$r,$self);
		}
		else
		{
			my $dbh = Boards::Post->db_Main;
			
			my $user = AppCore::Common->context->user;
			my $can_admin = $user && $user->check_acl($self->config->{admin_acl}) ? 1 :0;
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
				#print STDERR "POLL: Postid: $postid, Timestamp: $req->{first_ts}\n" if $postid;
				my $sth = $dbh->prepare_cached(
					'select b.*, u.photo as user_photo, u.user as username '.
					'from board_posts b left join users u on (b.posted_by=u.userid) '.
					"where (boardid=? or $user_wall_clause) and timestamp>? ".
					($postid? 'and top_commentid=?':' ').
					'and deleted=0 order by timestamp');
				
				my @args = ($board->id, $req->{first_ts});
				push @args, $postid if $postid;
				
				$sth->execute(@args);
				my @results;
				my $ts;
				while(my $b = $sth->fetchrow_hashref)
				{
					my $x = $self->load_post_for_list($b,$board_folder_name,$can_admin);
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
			#my $len = $req->len || $AppCore::Config::BOARDS_POST_PAGE_LENGTH;
			#$len = $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH if $len > $AppCore::Config::BOARDS_POST_PAGE_MAX_LENGTH;
			
			my $len = 0; # disable paging
			
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
			my $data = $Boards::BoardDataCache{$cache_key};
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
					my $find_posts_sth = $dbh->prepare_cached("select b.postid from board_posts b where (boardid=? or $user_wall_clause) and top_commentid=0 and deleted=0 order by timestamp desc limit ?,?");
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
						'order by timestamp');
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
					push @tmp_list, $self->load_post_for_list($b,$board_folder_name,$can_admin);
				}
				
				my $threaded = $self->thread_post_list(\@tmp_list);
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
				$Boards::BoardDataCache{$cache_key} = $data;
				#print STDERR "[-] BoardDataCache Cache Miss for board $board (key: $cache_key)\n"; 
				
				#die Dumper \@list;
			}
			else
			{
				#print STDERR "[+] BoardDataCache Cache Hit for board $board\n";
				
				# Go thru and update approx_time_ago fields for posts and comments
				if((time - $data->{timestamp}) > $Boards::APPROX_TIME_REFERESH)
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
			
			$self->forum_page_hook($output,$board);
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($output);
				return $r->output_data("application/json", $json);
				#return $r->output_data("text/plain", $json);
			}
			
			#my $tmpl = $self->get_template($self->config->{list_tmpl} || 'list.tmpl');
			my $tmpl = $self->get_template('editor.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			#$tmpl->param(user_email_md5 => md5_hex($user->email)) if $user && $user->id;
			$tmpl->param(boards_indent_multiplier => $Boards::INDENT_MULTIPLIER);
			
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
			
			#$self->apply_video_providers($tmpl);
			
			#my $view = Content::Page::Controller->get_view('sub',$r);
			#$view->breadcrumb_list->push($board->title,"$bin/$folder_name",0);
			#$view->output($tmpl);
			#return $r;
			
			return WriteBlock->output($r,$tmpl);
		}
	}
	
	# TODO reimpl can_user_edit
	#if(!$controller->can_user_edit($post))
	
	
	
# 	sub new_post_hook
# 	{
# 		my $class = shift;
# 		my $tmpl = shift;
# 		#die "new post hook";
# 		my $can_epa = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($EPA_ACL);
# 		$tmpl->param(can_epa=>$can_epa);
# 	}
# 	
# 	sub create_new_thread
# 	{
# 		my $self = shift;
# 		my $board = shift;
# 		my $req = shift;
# 		my $user = shift;
# 		
# 		my $can_epa = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($EPA_ACL);
# 		$req->{epa} = 0 if !$can_epa;
# 		
# 		# Attempt to guess the type of post based on the text - only if the user didn't specify it manually
# 		my $tag = $req->{tag} || 'talk';
# 		if(!$req->{user_clicked_tag})
# 		{
# 			if($req->{comment} =~ /(please\s[^\.\!\?]*?)?remember|pray/i)
# 			{
# 				$tag = 'pray';
# 			}
# 			elsif($req->{comment} =~ /(prais|thank)/i)
# 			{
# 				$tag = 'praise';
# 			}
# 		}
# 		
# 		# If an 'e-alert', then create a dated, nouned subject
# 		if($req->{epa})
# 		{
# 			my $noun = $self->alert_noun($tag);
# 			my $dt = AppCore::Web::Common::dt_date();
# 		
# 			$req->{subject} = $noun.' '.$dt->month.'.'.$dt->day.'.'.substr(''.$dt->year,2,2).': '.$self->guess_subject($req->{comment});
# 		}
# 	
# 		# Rely on superclass to do the actual post creation
# 		my $post = $self->SUPER::create_new_thread($board, $req, $user);
# 		
# 		# Store the tag in the ticker_class member for easy access in the template rendering
# 		$post->ticker_class($tag);
# 		$post->update;
# 		
# 		$post->ticker_class; # this is required for some reason - otherwise the ajax-post that loads doesnt read the ticker_class - but a full page reload does!
# 		
# 		#print STDERR "Assigning ticker class: $tag (".$post->ticker_class.")\n";
# 		
# 		# If an e-alert, tag the post with the e-alert tag and the noun, then send the emails
# 		if($req->{epa})
# 		{
# 			my $noun = $self->alert_noun($tag);
# 			$post->add_tag($noun);
# 			$post->add_tag('e-alert');
# 			
# 			$self->send_email_alert($post);
# 		}
# 		
# 		# TODO Honor user prefs re email notice on specific tags
# 		
# 		return $post;
# 	}
# 	
# 	sub send_email_alert
# 	{
# 		my $self = shift;
# 		my $post = shift;
# 		
# 		my $tag = lc $post->ticker_class;
# 		
# 		if($tag !~ /^(talk|pray|praise)$/)
# 		{
# 			print STDERR __PACKAGE__."::send_email_alert(): Unknown ticker class '$tag' - not alerting\n";
# 		}
# 		
# 		my $noun = $self->alert_noun($tag);
# 		
# 		# TODO Honor user prefereances re opt outs
# 		
# 		my @users;# = AppCore::User->retrieve_from_sql('email <> ""'); # and allow_email_flag!=0');
# 		
# # 		# Just for Debugging ...
# # 		@users = map { AppCore::User->retrieve($_) } qw/1 51/;
# 		
# 		# Extract email addresses
# 		my @emails = map { $_->email } @users;
# 		
# 		# Make emails unique (dont send the same email twice to the same user)
# 		my %unique_map = map { $_ => 1 } @emails;
# 		@emails = keys %unique_map;
# 		
# 		my $subject = $post->subject; # the subject was set correctly in create_new_thread()
# 		my $body = AppCore::Web::Common->html2text($post->text);
# 		$body =~ s/\n\s*$//g;
# 		
# 		my $folder = $post->folder_name;
# 		
# 		my $text = "Dear Friends,\n\n".
# 			$body.
# 			"\n\nPastor Bryan".
# 			"\n\n-----\n".qq{
# 
# Here's a link to this $noun posted on the PHC Website:
#     ${AppCore::Config::WEBSITE_SERVER}/connect/talk/$folder
#     
# Cheers!
# };
# 		AppCore::Web::Common->send_email(\@emails, $subject, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
# 		
# 		
# 	}
# 	
# 	sub alert_noun
# 	{
# 		my $self = shift;
# 		
# 		my $tag = lc shift || 'talk';
# 		
# 		my $noun = "e" . 
# 			($tag eq 'pray'   ? 'Prayer' :
# 			 $tag eq 'praise' ? 'Praise!' : 'Info') . "Alert";
# 		
# 		return $noun;
# 	}
	
	
};
1;
