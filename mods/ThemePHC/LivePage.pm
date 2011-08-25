use strict;

package ThemePHC::LivePage;
{
	# Inherit both the AppCore::Web::Module and Page Controller.
	# We use the Page::Controller to register a custom
	# page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	use AppCore::Web::Common;
	
	# For json communication
	use JSON qw/encode_json decode_json/;
	
	# Access ::Controller for get_view()
	use Content::Page;
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Live Stream Page','Provides Live Feed page and associated content',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	# Access video lists
	use ThemePHC::Videos;
	
	# Chatting functionality
	# Note: We inherit from 'Boards' to make it easy to override hooks, etc - but we 
	# dont really use much of the subclass other than routing stuff to Boards for chatting
	our $CHAT_BOARD = Boards::Board->find_or_create(title=>'PHC Live Feed Chat', folder_name=>'live_feed_chat');
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config({
			
			tmpl_incs 	=> 
			{
				newpost	=> 'mods/ThemePHC/tmpl/boards/inc-newpostform-livepage.tmpl',
				postrow => 'mods/ThemePHC/tmpl/boards/inc-postrow-livepage.tmpl',	
			},
		});
		
		return $self;
	};
	
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
		return $self->live_page($req,$r);
	};
	
	sub live_page
	{
		my $self = shift;
		my ($req,$r) = @_;
		
 		my $user = AppCore::Common->context->user;
 		
 		my $sub_page = $req->next_path;
 		
 		my $board = $CHAT_BOARD;
 		if($sub_page eq $board->folder_name)
 		{
 			$req->push_page_path($req->shift_path);
 			$sub_page = $req->next_path;
 		}
 		
 		my $post;
 		$post = Boards::Post->retrieve($sub_page) || Boards::Post->by_field(folder_name => $sub_page) if $sub_page;
 		
 		#print STDERR __PACKAGE__."->live_page: sub_page:'$sub_page', post:$post\n";
		
 		if($sub_page eq 'new' || $sub_page eq 'post' || $sub_page eq 'edit' || $post)
		{
			# Board actions - TODO test and see if more actiosn need to be routed
			$self->SUPER::board_page($req,$r,$board);
		}
		elsif($sub_page eq 'more_videos')
		{
			my $video_controller = AppCore::Web::Module->bootstrap('ThemePHC::Videos');
 			
 			my $data = $video_controller->load_post_list($ThemePHC::Videos::VIDEOS_BOARD, {idx=>$req->{idx}, len=>10});  # Load top 10 videos
			foreach my $post (@{$data->{posts}})
			{
				$post->{video_attach} = $self->create_video_links($post->{text},1);
			}
			
			
			my $json = encode_json($data);
			return $r->output_data("application/json", $json);
		}
		elsif($sub_page eq 'chatframe')
		{
			# 	Moved the chat code into an iframe because it messes with the live feed:
			# 	What happens:
			# 	1. User visits page
			# 	2. Ustream feed loads
			# 	3. User makes a post in chat
			# 	4. Somehow, the post's insertion into the DOM causes the Ustream feed to RE-INITALIZE, triggering any preroll ads to re-play again
			# 	
			# 	Note that subsequent comments in the chat don't trigger a reload of the feed, just the first comment on page load.
			# 	It doesn't help to put the ustream feed in an iframe - chat still bugs it. However, with the chat code itself in the iframe,
			# 	somehow that keeps it from bothering the ustream feed.
			
			my $tmpl = $self->get_template('live/chat.tmpl');
			
			#### Insert Boards-related data
 			
 			# Load posts
			my $data = $self->load_post_list($board, $req);
			if($req->output_fmt eq 'json')
			{
				# http://beta.mypleasanthillchurch.org/connect/groups/?first_ts=2011-07-15+11%3A09%3A30&output_fmt=json&mode=poll_new_posts
				my $json = encode_json($data);
				return $r->output_data("application/json", $json);
				#return $r->output_data("text/plain", $json);
			}
			
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('posts_'.$_ => $data->{$_}) foreach keys %$data;
			$tmpl->param($_ => $data->{$_}) foreach keys %$data; # since we are using Board's list.tmpl, they expect the params with now prefix
			$tmpl->param(boards_indent_multiplier => $Boards::INDENT_MULTIPLIER);
			my $tmpl_incs = $self->config->{tmpl_incs} || {};
			#use Data::Dumper;
			#die Dumper $tmpl_incs;
			foreach my $key (keys %$tmpl_incs)
			{
				$tmpl->param('tmpl_inc_'.$key => $tmpl_incs->{$key});
			}
			
			$tmpl->param(boards_list_as_widget => 1);
			
			# Since a theme has the option to inline a new post form in the post template,
			# provide the controller a method to hook into the template variables from here as well
			$self->new_post_hook($tmpl,$board);
			
			# Note forced stringification required below.
			$tmpl->param('posts_approx_time' => ''.approx_time_ago($data->{first_ts}));
			
			# For videos linked in posts...
			$self->apply_video_providers($tmpl);
			
			return $r->output($tmpl);
		}
		else
 		{
 			my $tmpl = $self->get_template('live/main.tmpl');
 			
 			#### Insert recent videos
 			my $video_controller = AppCore::Web::Module->bootstrap('ThemePHC::Videos');
 			my $video_list = $video_controller->load_post_list($ThemePHC::Videos::VIDEOS_BOARD, {idx=>0, len=>10});  # Load 10 most recent videos
 			foreach my $post (@{$video_list->{posts}})
			{
				$post->{video_attach} = $self->create_video_links($post->{text},1);
				$post->{data} = decode_json($post->{extra_data} || '{}');
				$post->{'data_'.$_} = $post->{data}->{$_} foreach keys %{$post->{data} || {}}; 
			}
			
 			$tmpl->param('videos_'.$_ => $video_list->{$_}) foreach keys %$video_list;
 			
 			
 			
 			my $view = Content::Page::Controller->get_view('sub',$r);
			#$view->breadcrumb_list->push('Groups Home',$self->module_url(),0);
			$view->breadcrumb_list->push("Live Video Feed",$self->module_url('/'.$sub_page),0);
			$view->output($tmpl);
			return $r;	
 		}
	}
}

1;