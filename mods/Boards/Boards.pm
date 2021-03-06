use strict;


package Boards::TextFilter::AutoLink;
	{ 
		use base 'Boards::TextFilter';
		__PACKAGE__->register("Auto-Link","Adds hyperlinks to text.");
		
		sub _add_http
		{
			local $_ = shift;
			return /^www\./ ? 'http://' . $_ : $_;
		}
		
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
			$$textref =~ s/([^'"\/<:-]|^)((?:(?:http|https|ftp|telnet|file):\/\/|www\.)([^\s<>'"]+))/$1.'<a href="'._add_http($2).'">'.$2.'<\/a>'/egi;
			# Changes:
			# - Added '-' to the first exclusion block [^...] to properly handle this case:
			#		<img src="http://cdn-www.i-am-bored.com/media/howwomenseetheworld.jpg" alt="" />
			# - Removed '>' to properly link stuff like:
			#		<p>http://www....</p>
			
			#print STDERR "AutoLink: After: ".$$textref."\n";
		};
		
	};
	
	
package Boards::TextFilter::ScribdWordpressParser;
	{ 
		use base 'Boards::TextFilter';
		__PACKAGE__->register("Scribd Wordpress Filter","Converts Scribd Wordpress Embed Code to HTML");
		
		my $HTML_FORMAT = 'flash'; # or html5
		
		sub _create_scribd_embed_html
		{
			my ($id,$key,$mode) = @_;
			
# 			<a title="View on Scribd" href="http://www.scribd.com/doc/${id}" style="margin: 12px auto 6px auto; font-family: Helvetica,Arial,Sans-serif; font-style: normal; font-variant: normal; font-weight: normal; font-size: 14px; line-height: normal; font-size-adjust: none; font-stretch: normal; -x-system-font: none; display: block; text-decoration: underline;">${title}</a>
			return $HTML_FORMAT eq 'flash' ?
			qq{
				 <object height="600" width="100%" type="application/x-shockwave-flash" data="http://d1.scribdassets.com/ScribdViewer.swf" style="outline:none" >
				 	<param name="movie" value="http://d1.scribdassets.com/ScribdViewer.swf">
				 	<param name="wmode" value="opaque">
				 	<param name="bgcolor" value="#ffffff">
				 	<param name="allowFullScreen" value="true">
				 	<param name="allowScriptAccess" value="always">
				 	<param name="FlashVars" value="document_id=${id}&access_key=${key}&page=1&viewMode=${mode}">
				 	<embed src="http://d1.scribdassets.com/ScribdViewer.swf?document_id=${id}&access_key=${key}&page=1&viewMode=${mode}" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" height="600" width="100%" wmode="opaque" bgcolor="#ffffff"></embed>
				 </object>
			} :
			qq|
				<iframe class="scribd_iframe_embed" src="http://www.scribd.com/embeds/${id}/content?start_page=1&view_mode=list&access_key=${key}" data-auto-height="true" data-aspect-ratio="0.779617834394905" scrolling="no" width="100%" height="600" frameborder="0"></iframe>
				<script type="text/javascript">(function() { var scribd = document.createElement("script"); scribd.type = "text/javascript"; scribd.async = true; scribd.src = "http://www.scribd.com/javascripts/embed_code/inject.js"; var s = document.getElementsByTagName("script")[0]; s.parentNode.insertBefore(scribd, s); })();</script>
			|;
		}
		
		# It just accepts a scalar ref and runs a regexp over the text (note the double $$ to deref)
		sub filter_text
		{
			my $self = shift;
			my $textref = shift;
			#print STDERR "AutoLink: Before: ".$$textref."\n";

			#Sample: [scribd id=64192688 key=key-uwgseze2p7s03ow8a8b mode=list]
			$$textref =~ s/\[scribd id=([^\s]+) key=([^\s]+) mode=([^\]]+)\]/_create_scribd_embed_html($1,$2,$3)/egi;
			
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
			url_regex	=> qr/(http:\/\/www.youtube.com\/watch\?v=[a-zA-Z0-9\-\_]+|http:\/\/youtu.be\/[a-zA-Z0-9\-\_]+)/,	# Used to find this provider's URL in content
			
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
			my ($code) = $url =~ /v=([a-zA-Z0-9\-\_]+)/;
			($code) = $url =~ /.be\/([a-zA-Z0-9\-\_]+)/ if !$code;
			#print STDERR "youtube url: $url, code: $code\n";
			return ($url, "http://img.youtube.com/vi/$code/1.jpg", $code);
		};
	};

package Boards::VideoProvider::UStream;
        {
                use base 'Boards::VideoProvider';
                __PACKAGE__->register({
                        name            => "UStream",                                           # Name isn't used currently
                        provider_class  => "video-ustream",                                     # provider_class is used in page to match provider to iframe template, and construct template and image ID's
                        url_regex       => qr/(http:\/\/www.ustream.tv\/recorded\/\d+)/,        # Used to find this provider's URL in content

                        iframe_size     => [480,302],                                           # The size of the iframe - used to animate the link block element size larger to accomidate the new iframe
                                                                                                # The iframe template is used by jQuery's template plugin to generate the iframe html
                        iframe_tmpl     => '<iframe title="UStream Video player" width="480" height="302" '.
                                                'src="http://www.ustream.tv/embed/recorded/${videoid}?v=3&amp;wmode=direct" '.
                                                'scrolling="no" frameborder="0" style="border: 0px none transparent;"></iframe>'
                });

                # Expected to return an array of (link URL, image URL, video ID) - videoId is set on the <a> tag in a custom 'videoid' attribute
                sub process_url
                {
                        my $self = shift;
                        my $url = shift;
                        my ($code) = $url =~ /recorded\/(\d+)/;
                        #print STDERR "ustream url: $url, code: $code\n";
			
			my $video_path = '/0/1/'.substr($code,0,2).'/'.substr($code,0,5).'/'.$code.'/1_8249750_'.$code;

			my $img = 'http://static-cdn1.ustream.tv/i/video/picture'.$video_path.',112x63,b,1:2.jpg';

                        return ($url, $img, $code);
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
				$(function(){
					setTimeout(function()
					{
						if(window.location.hash.indexOf("autoplay")>0 &&
						$('a.video-vimeo').length == 1)
						{
							var link = $('a.video-play-link');
							var func = window.VidPlay;
							//console.debug("autoplay: found "+link.lengths+" links: "+link.get(0)+", func: "+func); 
							link.playVideo = func;
							link.playVideo();
							//alert('trying to autoplay');
						}
					}, 100);
				});
				// This handles the thumbnail callback from vimeo - grabs the url, sets it on the image and resizes the image accordingly
				function showThumb(data)
				{
					if(!data[0])
						return;
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
			return ($url, AppCore::Config->get("WWW_ROOT")."/images/blank.gif", $code);
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
	use JSON::XS qw/encode_json decode_json/;
	
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
	our $PREF_EMAIL_ALL      = AppCore::User::PrefOption->register(__PACKAGE__, 'Notification Preferences', 'Send me an email for all new posts', {default_value=>0});  # defaults to bool for datatype and true for default value
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
				
				notification_methods => [qw/notify_via_email notify_via_facebook/]
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
		my $new_binpath = AppCore::Config->get("DISPATCHER_URL_PREFIX") . $req->page_path; # this should work...
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
			my $board = $self->get_board_from_req($req);
			if(!$board)
			{
				return $r->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
			}
		
			return $self->board_page($req,$r,$board);
		}
		else
		{
			my $tmpl = $self->get_template($self->config->{main_tmpl} || 'main.tmpl');
			$tmpl->param(board_nav => $self->macro_board_nav());
			
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});;
			$tmpl->param(can_admin=>$can_admin);
		
			my @groups = Boards::Group->search(hidden=>0);
			@groups = sort {$a->sort_key cmp $b->sort_key} @groups;
			
			my $appcore = AppCore::Config->get("WWW_ROOT");
			
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
	
	sub get_board_from_req
	{
		my $self = shift;
		my $req = shift;
		
		my $folder_name = $req->shift_path;
		
		my $board = Boards::Board->by_field(folder_name => $folder_name);
		if(!$board)
		{
			$! = $@ = 'No such board';
			return undef;
		}
		
		$req->push_page_path($folder_name);
		
		return $board;
	}
	
	sub subpage_action_hook
	{
		return 0;
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
	our %ControllerCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing cached data...\n";
		%BoardDataCache = ();
		%PostDataCache = ();
		@TextFilters = ();
		@VideoProviders = ();
		%ControllerCache = ();
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__,'prime_cache');
	
	sub prime_cache
	{
		my $self = shift;
		
		#print STDERR __PACKAGE__."->prime_cache: Loading text filters and video providers\n";
		$self->load_video_providers;
		$self->load_text_filters;
		
# 		my @boards = Boards::Board->retrieve_all; #search(board_userid => 0);
# 		foreach my $board (@boards)
# 		{
# 			print STDERR __PACKAGE__."->prime_cache: Loading board # $board - ".$board->title."\n";
# 			$self->load_post_list($board);
# 		}
		
	}
	
	sub load_text_filters
	{
		if(!@TextFilters)
		{
			# only load the 'enabled' filters (all are enabled by default)
			@TextFilters = Boards::TextFilter->search(is_enabled=>1);
		}
	}	
	
	sub get_controller
	{
		my $self = shift;
		my $board = shift;
		
		my $controller = $self;
		
		if(!$ControllerCache{$board->id})
		{
			#die $board->folder_name;
			if($board->forum_controller)
			{
				#eval 'use '.$board->forum_controller;
				#die $@ if $@ && $@ !~ /Can't locate/;
				
				$controller = AppCore::Web::Module->bootstrap($board->forum_controller);
				$controller->binpath($self->binpath);
			}
			
			
			$ControllerCache{$board->id} = $controller;
		}
		else
		{
			$controller = $ControllerCache{$board->id};
		}
		
		$controller->binpath($self->binpath) if $controller ne $self;
		
		#print STDERR "get_controller: mark6: final bin:".$controller->binpath."\n";
		
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
			
			$req->push_page_path($req->shift_path); # put the user onto the end of the page path
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
		my $board = shift; 
		
		my $folder_name = $board->folder_name; 
		my $boardroot_url = $board->boardroot_url;
		
		# Make sure we are being accessed thru a Content::Page object if one exists with "our name on it", so to speak
		if(!$boardroot_url || !$req->{page_obj})
		{
			my $try_redir_base = 0;
			if($boardroot_url)
			{
				my $cur_url = $req->page_path; #."/$folder_name";
				
				#print STDERR get_full_url().": board_page: Matched folder $folder_name to pageid $page, page url:".$page->url.", current path: $cur_url\n";
				if($boardroot_url ne $cur_url)
				{
					$try_redir_base = $boardroot_url;
				}
			}
			
			if(!$try_redir_base || !$boardroot_url)
			{
				my $sth = ($self->{_sth_pagecheck} ||= Content::Page->db_Main->prepare('select pageid from `'.Content::Page->table.'` where url like ? and typeid=?'));
				$sth->execute("%/${folder_name}",$PAGE_TYPEID);
				if($sth->rows)
				{
					my $page = Content::Page->retrieve($sth->fetchrow);
					my $cur_url = $req->page_path; #."/$folder_name";
					
					$boardroot_url = $cur_url;
					if($board->boardroot_url ne $boardroot_url)
					{
						$board->boardroot_url($boardroot_url) ;
						$board->update; # trashes cache!
					}
					
					#print STDERR get_full_url().": board_page: Matched folder $folder_name to pageid $page, page url:".$page->url.", current path: $cur_url\n";
					if($page->url ne $cur_url)
					{
						$try_redir_base = $page->url;
					}
				}
			}
			
			if($try_redir_base)
			{
				my $new_url = $try_redir_base.($req->path?"/".join('/',$req->path_info):"").($ENV{QUERY_STRING} ? '?'.$ENV{QUERY_STRING} : '');
				if(get_full_url() ne $new_url)
				{
					#print STDERR get_full_url().": board_page: Redirecting to $new_url\n" unless $new_url =~ /poll/;
					return $r->redirect($new_url);
				}
			}
		}
		
		
		if($boardroot_url)
		{
			#$self->binpath('');
		}
		
		
		my $controller = $self->get_controller($board);
		
		my $sub_page = $req->next_path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = $self->binpath;
		my $page_path = $req->page_path;
		
		$boardroot_url = "$bin/$folder_name" if !$boardroot_url;
		
		#die Dumper $sub_page,$req, $bin, $page_path;
		
		if($sub_page eq 'post')
		{
			#$controller->{debug_extra_data} = 1;
				
			my $post = $controller->create_new_thread($board,$req);
			#print STDERR "[XTRADAT] Raw \$post right after create:".Dumper($post) if $controller->{debug_extra_data};
			
			$controller->send_notifications('new_post',$post);
			#$r->redirect(AppCore::Common->context->http_bin."/$section_name/$folder_name#c$post");
			
			#print STDERR "[DEBUG] Create new thread done, upload flag: ".$post->data->get('needs_uploaded')."\n";
			
			if($req->output_fmt eq 'json')
			{
				my $b = $controller->load_post_for_list($post,{board_folder_name => $board->folder_name, boardroot_url => $boardroot_url});
				
				#use Data::Dumper;
				#print STDERR "Created new postid $post, outputting to JSON, values: ".Dumper($b,$post,$post->extra_data);
				
				my $json = encode_json($b);
				return $r->output_data("application/json", $json);
			}
			
			return $r->redirect($page_path);
		}
		elsif($sub_page eq 'new')
		{
			my $tmpl = $self->get_template($controller->config->{new_post_tmpl} || 'new_post.tmpl');
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $controller->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $controller->config->{long_noun}  || 'Bulletin Boards');
			$tmpl->param(post_url => "$page_path/post");
			
			#die $controller;
			$controller->new_post_hook($tmpl,$board);
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('New Post',"$page_path/new",0);
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
			my @output_list = map { $controller->load_post($_,1) } @posts; # 1 = dont count this load as a 'view'
			foreach my $b (@output_list)
			{
				$b->{bin}         = $bin;
				$b->{pp}	  = $page_path;
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
			
			return $r->redirect($page_path);
			
		}
		elsif($sub_page eq 'upload_photo')
		{
			# to move bulk upload files
			use File::Copy;

# 			our $UPLOAD_TMP_WWW     = '/appcore/mods/ThemePHC/audio_upload_tmp';
# 			our $UPLOAD_TMP         = '/var/www/html'.$UPLOAD_TMP_WWW;
# 			our $RECORDING_WWW_ROOT = '/appcore/mods/ThemePHC/audio_recordings';	
# 			our $RECORDING_DOC_ROOT = '/var/www/html'.$RECORDING_WWW_ROOT;
# 			our $BULK_UPLOAD_ROOT   = '/home/phc/BulkTrackUpload/';
				
			my $filename = $req->{upload};
			#$skin->error("No Filename","No filename given") if !$filename;
			if(!$filename)
			{
				print STDERR "INFO: $sub_page: No file given to upload.\n";
				return $r->error('No File','You must select a file');
				#return $r->output_data('text/html',"<html><head><script>parent.do_upload(false);alert('You must select a file to upload.')</script></head></html>\n");
				
			}
			
			$filename =~ s/^.*[\/\\](.*)$/$1/g;
			my ($ext) = ($filename=~/\.(\w{3})$/);
			
			if(lc $ext !~ /(png|bmp|jpg|jpeg|gif)/i)
			{
				print STDERR "INFO: $sub_page: '$ext' is not an image extension.\n";
				#return $r->output_data('text/html',"<html><head><script>parent.do_upload(false);alert('Only MP3 files are allowed - the file you selected was a \"".uc($ext)."\" file.')</script></head></html>\n");
				return $r->error('Invalid File Type','Sorry, you can only upload photos.');
			}
			
			my $written_filename = "/tmp/$$.$ext";
			
# 			my $file_path = $UPLOAD_TMP."/recording_".($recording->id);
# 			my $file_url  = $RECORDING_WWW_ROOT."/recording_".($recording->id);
# 			system("mkdir -p $file_path");
			
			#my $abs = "$file_path/$written_filename";
			
			print STDERR "Uploading [$filename] to [$written_filename], ext=$ext\n";
			
			my $fh = main::upload('upload');
			
			open UPLOADFILE, ">$written_filename" || warn "Cannot write to $written_filename: $!"; 
			binmode UPLOADFILE;
			
			while ( <$fh> )
			{
				print UPLOADFILE $_;
			}
			
			close(UPLOADFILE);
			
			# Now, get md5 of file contents to determine final filename - that way, exact same images can be uploaded even if file names are different
			my $file_md5 = `md5sum $written_filename`;
			$file_md5 =~ s/[\r\n]//g;
			$file_md5 =~ s/^([^\s]+).*$/$1/g;
			
			my $local_photo_url = "/mods/User/user_photos/upload$file_md5.jpg";
			my $file_path = AppCore::Config->get('APPCORE_ROOT') . $local_photo_url;
			my $abs_photo_url = AppCore::Config->get('WEBSITE_SERVER') . AppCore::Config->get('WWW_ROOT') . $local_photo_url;
			
			my $local_photo_url_thumb = "/mods/User/user_photos/upload$file_md5-small.jpg";
			my $file_path_thumb = AppCore::Config->get('APPCORE_ROOT') . $local_photo_url_thumb;
			my $abs_photo_url_thumb = AppCore::Config->get('WEBSITE_SERVER') . AppCore::Config->get('WWW_ROOT') . $local_photo_url_thumb;
			
			my $exif_data = `exiftool $written_filename -CreateDate -Caption-Abstract`;
			my @lines = split /\n/, $exif_data;
			
			my $date = shift @lines;
			$date =~ s/^(.*?):\s+//g;

			my $caption = shift @lines;
			$caption =~ s/^(.*?):\s+//g;
			
			my $title = guess_title($filename);
			$title =~ s/\.\w+$//g;
			
			#$title = "Photo ".$date if $title =~ /^dsc_/i;
			#$caption .= ($caption?' ':'')."(Photo taken ".$date.")";
						
			# Reformat Date
			my ($year,$month,$day,$hour,$min,$sec) = $date =~ /(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
			my $yr = substr($year,2,4);
			$title = "Photo ".($month+0)."/".($day+0)."/".$yr." $hour:$min" if $title =~ /^dsc_/i;
			$caption .= ($caption?' ':'')."(Photo taken ".($month+0)."/".($day+0)."/".$yr." at $hour:$min)";
	
			# Effect the move
			print STDERR "Moving [$written_filename] to file path [$file_path]\n";
			move($written_filename, $file_path);
			
			# Resize to thumbnail
			print STDERR "Resizing [$file_path] to file path [$file_path_thumb] - 120x120\n";
			system("convert $file_path -resize 120x120 $file_path_thumb");
			
			print STDERR "ABS URL: $abs_photo_url\nTitle: '$title'\nCaption: '$caption'\n";
			
# 			if($req->output_fmt eq 'json')
# 			{
				my $b = {
					link	=> $abs_photo_url,
					picture	=> $abs_photo_url_thumb,
					name	=> $title,
					caption	=> '',
					description	=> $caption,
				};
				
				# Recursive - not really, just kinda fun :-)
				$b->{attach_data} = encode_entities(encode_json($b));
				
				my $json = encode_json($b);
				print STDERR "Upload photo JSON response: $json\n";
				return $r->output_data('application/json', $json);
# 			}
# 			
# 			my $cb = "parent._upload_cb($recording,'$t_num','$t_title','$t_len','$t_file')";
# 			#print STDERR "Callback: $cb\n";
# 			
# 			return $r->output_data('text/html',"<html><head><script>$cb</script></head></html>\n");
			
		}
		elsif($sub_page)
		{
                        if($controller->subpage_action_hook($sub_page, $req, $r))
                        {
                                return $r;
                        }

			return $self->post_page($req,$r,$controller);
		}
		else
		{
			my $output = $controller->load_post_list($board,$req);
			
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json($output);
				return $r->output_data("application/json", $json);
				#return $r->output_data("text/plain", $json);
			}
			
			my $user = AppCore::Common->context->user;
			
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
			$view->breadcrumb_list->push($board->title,$page_path,0);
			$view->output($tmpl);
			return $r;
		}
	}
	
	sub load_post_list
	{
		my $self = shift;
		my $board = shift;
		my $req = shift || {};
		my $controller = shift || $self->get_controller($board);
		
		my $dbh = Boards::Post->db_Main;
			
		my $user = AppCore::Common->context->user;
		my $can_admin = $user && $user->check_acl($controller->config->{admin_acl}) ? 1 :0;
		my $board_folder_name = $board->folder_name;
		
		my $bin = $self->binpath;
		my $boardroot_url = $board->boardroot_url ? $board->boardroot_url : "$bin/$board_folder_name"; 
		
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
				'and deleted=0 order by timestamp desc, postid desc');
			
			my @args = ($board->id, $req->{first_ts});
			push @args, $postid if $postid;
			push @args, $from_str if $from_str;
			
			$sth->execute(@args);
			my @results;
			my $ts;
			while(my $b = $sth->fetchrow_hashref)
			{
				my $x = $controller->load_post_for_list($b,{board_folder_name => $board_folder_name,can_admin => $can_admin, boardroot_url => $boardroot_url});
				$ts = $x->{timestamp};
				push @results, $x;
			}
			
			my $output = 
			{ 
				list	=> \@results,
				count	=> scalar @results,
				last_ts	=> $ts,
			};
			
# 			my $json = encode_json($output);
# 			return $r->output_data("application/json", $json) if $req->output_fmt eq 'json';
# 			return $r->output_data("text/plain", $json);
			return $output;
		}
		
		# Get the current paging location
		my $idx = $req->{idx} || 0;
		my $len = $req->{len} || $controller->config->{list_length} || AppCore::Config->get("BOARDS_POST_PAGE_LENGTH");
		$len = AppCore::Config->get("BOARDS_POST_PAGE_MAX_LENGTH") if $len > AppCore::Config->get("BOARDS_POST_PAGE_MAX_LENGTH");
		
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
				my $sql_ids = "select b.postid from board_posts b where (boardid=? or $user_wall_clause) and top_commentid=0 and deleted=0 order by timestamp desc
, postid desc limit ?,?";
				my $find_posts_sth = $dbh->prepare_cached($sql_ids);
				$find_posts_sth->execute($board->id, $idx, $len);
				
				#print STDERR "sql_ids: '$sql_ids', $idx, $len, ".$board->id."\n";

				my @posts;
				push @posts, $_ while $_ = $find_posts_sth->fetchrow;
				
				# Keep user from getting a "dirty" error by giving a simple error
				if(!@posts)
				{
					#return $r->error("No posts at index ".($idx+0));
					#@posts = (0); # Allow the page to be empty :-)
				}
				
				my $list = join ',',  @posts;
				
				# Now do the actual query that loads both posts and comments in one gos
				my $sql = 'select p.*,b.folder_name as original_board_folder_name,b.title as board_title, u.photo as user_photo, u.user as username from board_posts p left join users u on (p.posted_by=u.userid), boards b '.
					"where (((p.boardid=? or $user_wall_clause)" . (@posts ? " and postid in (".$list.")" : "").")". (@posts ? " or top_commentid in (".$list.")" : ""). ") and p.deleted=0 and p.boardid=b.boardid ".
					'order by timestamp asc, postid asc'; # order will be inverted with a 'reverse' call, below
				$sth = $dbh->prepare_cached($sql);
				
				#print STDERR "$sql\n".$board->id."\n";
			}
			
			$sth->execute($board->id);
			
			# First, prepare all the post results (posts and comments) at the same time
			# Create a crossref of posts to data objects for the next block which puts the comments with the parents
			my @tmp_list;
			my %crossref;
			my $first_ts = undef;
			my $counter = $idx;
			while(my $b = $sth->fetchrow_hashref)
			{
				$first_ts = $b->{timestamp};# if !$first_ts;
				$b->{reply_count} = 0;
				$b->{board_userid} = $board_userid;
				$b->{post_number} = $counter ++; 
				#die Dumper $b;
				push @tmp_list, $controller->load_post_for_list($b,{board_folder_name => $board_folder_name,can_admin => $can_admin, boardroot_url => $boardroot_url});
			}
			
			my $threaded = $controller->thread_post_list(\@tmp_list, undef, undef, $board->board_userid);
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
			board	  => $board_ref,
			posts	  => $data->{list},
			idx	  => $idx,
			idx1	  => $idx + 1,
			len	  => $max_idx    <  $len     ? $max_idx : $len,
			idx2	  => $idx + $len >  $max_idx ? $max_idx : $idx + $len,
			next_idx  => $next_idx   >= $max_idx ? 0        : $next_idx,
			first_ts  => $data->{first_timestamp}, # Used for in-page polling dyanmic new content inlining
			max_idx   => $max_idx,
			can_admin => $can_admin,
			fb_sync_enabled => $board->fb_sync_enabled,
		};
		
		$controller->forum_page_hook($output,$board);
		
		return $output;
		
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
		my $opts = shift;
			
		use Data::Dumper;
		
		#print STDERR "[XTRADAT] Raw \$post and \$opts from args:".Dumper({post=>$post,opts=>$opts}) if $self->{debug_extra_data};
		
		my $board_folder_name	= $opts->{board_folder_name} || undef;
		my $can_admin		= $opts->{can_admin} || undef; # will be decided below if not set
		my $dont_incl_comments	= $opts->{dont_incl_comments} || 0;
		
		if(!defined $can_admin)
		{
			$can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
		}
		
		my $short_len             = AppCore::Config->get('BOARDS_SHORT_TEXT_LENGTH')     || $SHORT_TEXT_LENGTH;
		my $last_post_subject_len = AppCore::Config->get('BOARDS_LAST_POST_SUBJ_LENGTH') || $LAST_POST_SUBJ_LENGTH;
		
		my $ref_name = ref $post;
		#print STDERR "Refname of post is '$ref_name', value '$post'\n";
		if($ref_name eq 'Boards::Post')
		{
			my $hash = {};
			$hash->{$_} = $post->{$_}."" foreach $post->columns;
			$hash->{extra_data} = $post->extra_data; # Hack??
			
			my $user = $post->posted_by;
			if($user && $user->id)
			{
				$hash->{username} = $user->user;
				$hash->{user_photo} = $user->photo;
				
				if(!$hash->{user_photo})
				{
					## HACK!!!
					eval {
						eval 'use ThemePHC::Directory';
						$hash->{user_photo} = PHC::Directory->photo_for_user($user);
						if($post->{user_photo})
						{
							$post->{poster_photo} = $post->{user_photo};
						}
					};
					print STDERR "Debug: error calling p4u: $@, post: $hash->{folder_name}, postid: $hash->{postid}\n" if $@;
					undef $@; 
				}
			}
			
			
			
			$hash->{board_userid} = $post->boardid ? $post->boardid->board_userid+0 : undef;
			#die Dumper $hash;
			
			$post = $hash;
		}
		else
		{
			if(!$post->{user_photo} && $post->{posted_by})
			{
				## HACK!!!
				eval {
					eval 'use ThemePHC::Directory';
					$post->{user_photo} = PHC::Directory->photo_for_user(AppCore::User->retrieve($post->{posted_by}));
					if($post->{user_photo})
					{
						$post->{poster_photo} = $post->{user_photo};
					}
				};
				print STDERR "Debug: error calling p4u: $@, post: $post->{folder_name}, postid: $post->{postid}\n" if $@;
				undef $@; 
			}
			else
			{
				#print STDERR "Debug: Not called p4u because user_photo is '$post->{user_photo}' or posted_by is '$post->{posted_by}', post: $post->{folder_name}, postid: $post->{postid}\n";
			}

		}
		
		#print STDERR "[XTRADAT] \$post:".Dumper($post) if $self->{debug_extra_data};
		if($post->{extra_data})
		{
			undef $@;
			eval
			{
				my $hash = JSON::XS::decode_json($post->{extra_data});
				#print STDERR "[XTRADAT] \$hash:".Dumper($hash) if $self->{debug_extra_data};
				if(ref $hash eq 'HASH')
				{
					$post->{'data_'.$_} = $hash->{$_} foreach keys %$hash;
					#print STDERR "[XTRADAT] \$post after foreach:".Dumper($post) if $self->{debug_extra_data};
					if($post->{data_attach_list})
					{
						my @tmp = @{$post->{data_attach_list} || []};
						foreach my $attachment (@tmp)
						{
							$attachment->{'post_class_'.$post->{post_class}} = 1;
							$attachment->{postid} = $post->{postid};
						} 
						
					}
					#die Dumper $post if $post->{data_has_multi_attach};
				}
			};
			warn "Error decoding extra data on postid $post->{postid}: $@" if $@;
		}
		else
		{
			#print STDERR "[XTRADAT] No {extra_data} in post\n" if $self->{debug_extra_data};
		}
		
		#my $board_folder_name = $board->{folder_name};
		my $folder_name = $post->{folder_name};
		#my $user = $post->{posted_by};
		my $bin = $self->binpath;
		#AppCore::Common::print_stack_trace() unless ref($self) ne 'ThemePHC::BoardsTalk' || $self->{stack} ++;
		#print STDERR "Boards->load_post_for_list: bin:".$bin.", ref:".ref($self)."\n";
		
		
		#my $b = {};
		
		my $b = $post;
		# Force stringification...
		## NOTE Assuming SQL Query already stringified everything. Assuming NOT from CDBI!!
# 		my @cols = $post->columns;
# 		$b->{$_} = $post->get($_). "" foreach @cols; #$post->columns;
		$b->{bin}         = $bin;
		$b->{appcore}     = $self->{_www_root} ||= AppCore::Config->get("WWW_ROOT");
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
		$b->{single_post_page} = 0 if !$b->{single_post_page};
		$b->{indent_is_odd}    = 0 if !$b->{indent_is_odd};
		$b->{board_userid}     = 0 if !$b->{board_userid};
		$b->{original_board_folder_name} = '';
		
		# More retarded jQuery tmpl plugin fixes
		$b->{post_class_photo} = 0;
		$b->{post_class_video} = 0;
		
		
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
		$short =~ s/(^[\s\n]+|[\s\n]+$)//g;
		
		$b->{short_text}  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
		$b->{short_text_has_more} = length($short) > $short_len || $b->{text} =~ '<img' || $b->{text} =~ '<object';
		
		my $clean_html = AppCore::Web::Common->text2html($b->{short_text});
		
		#$b->{short_text_html} =~ s/([^'"])((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/$1<a href="$1">$2<\/a>/gi;
		
		# Moved to the TEXT_FILTERS list to use as an example
		#$clean_html = $self->create_inline_links($clean_html);
		
		# Run all Boards::TextFilter on both the clean_html and the full text
		$self->load_text_filters;
		
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
		if($b->{data_has_attach} && $b->{post_class} eq 'video')
		{
			my $text = $text_tmp;
			
			# Make sure it's loaded...
			$self->load_video_providers;
			
			VIDEO_PROVIDER: foreach my $provider (@VideoProviders)
			{
				my $config = $provider->controller->config;
				my $rx = $config->{url_regex};
				my ($url) = $text =~ /$rx/;
				if($url)
				{
					my ($link_url, $thumb_url, $videoid) = $provider->controller->process_url($url);
					
					my $provider_class = $config->{provider_class};
					
					
					$b->{video_provider_class} = $provider_class;
					$b->{videoid} = $videoid;
					#$b->{video_image_id} =
					 
# 					#my ($code) = $url =~ /v=(.+?)\b/;
# 					#$b->{short_text_html} .= '<hr size=1><iframe title="YouTube video player" width="320" height="240" src="http://www.youtube.com/embed/'.$code.'" frameborder="0" allowfullscreen></iframe>';;
# 					my $attach = qq{
# 						<hr size=1 class='post-attach-divider'>
# 						<a href='$link_url' class='video-play-link $provider_class' videoid='$videoid'>
# 						<img src="$thumb_url" border=0 id='$provider_class-$videoid'>
# 						<span class='overlay'></span>
# 						</a>
# 					};
# 					return $attach if $return_first;
# 					$text .= $attach;
					 
					last VIDEO_PROVIDER;
				}
			}
			
			$b->{text}       = $text_tmp;
			$b->{clean_html} = $clean_html;
			
			#return $text;
		}
		else
		{
			$b->{text}       = $self->create_video_links($text_tmp);
			$b->{clean_html} = $self->create_video_links($clean_html);
		}
		
		# Trim whitespace off start/end of html
 		$b->{clean_html} =~ s/(^[\s\n]+|[\s\n]+$)//g;
		
		#use Data::Dumper;
		#die Dumper($b) if $b->{postid} == 10585;
		
		
		# just for jQuery's sake - the template converter in AppCore::Web::Result treats variables ending in _html special
		$b->{text_html} = $b->{text} = AppCore::Web::Common->clean_html($b->{text}); 
		#timemark("html processing");
		
		
		$b->{poster_email_md5} = md5_hex($b->{poster_email});
		$b->{approx_time_ago}  = approx_time_ago($b->{timestamp});
		$b->{pretty_timestamp} = pretty_timestamp($b->{timestamp});
		
		my $boardroot = $opts->{boardroot_url} ? $opts->{boardroot_url} : "$bin/$board_folder_name";
		$b->{postroot_url } = $opts->{postroot_url};
		$b->{boardroot_url} = $boardroot; 
		
		my $reply_to_url   = "${boardroot}/${folder_name}/reply_to";
		my $delete_base    = "${boardroot}/${folder_name}/delete";
		my $like_url       = "${boardroot}/${folder_name}/like";
		my $unlike_url     = "${boardroot}/${folder_name}/unlike";
		
		$b->{reply_to_url} = $reply_to_url;
		$b->{delete_base}  = $delete_base;
		$b->{like_url}     = $like_url;
		$b->{unlike_url}   = $unlike_url;
		
		$b->{'post_class_'.$b->{post_class}} = 1;
		
		Boards::Post::Like->like_data_for_post($b->{postid}, $b);
		
		if($b->{to_userid} && $b->{to_userid} != $b->{posted_by})
		{
#			die Dumper $b;
			my $to_user = ref $b->{to_userid} ? $b->{to_userid} : AppCore::User->retrieve($b->{to_userid});
			if($to_user)
			{
				$b->{to_user_display} = $to_user->display;
				$b->{to_user} = $to_user->user;
			}
		}
		
		#$b->{text} = PHC::VerseLookup->tag_verses($b->{text});
		
		#die Dumper $b if $short =~ /his passion, and his words/;
		
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
		my $return_first = shift || 0;
		
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
				my $attach = qq{
					<hr size=1 class='post-attach-divider'>
					<a href='$link_url' class='video-play-link $provider_class' videoid='$videoid'>
					<img src="$thumb_url" border=0 id='$provider_class-$videoid'>
					<span class='overlay'></span>
					</a>
				};
				return $attach if $return_first;
				$text .= $attach; 
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
		my $dont_count_view = shift || 0;
		my $more_local_ctx  = shift || undef;
		my $dont_incl_comments = shift || 0;
		
		my $first_ts = $post->timestamp;
		
		#print_stack_trace();
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
			
			my $boardroot_url = $post->boardid->boardroot_url;
			$boardroot_url = "$bin/$board_folder_name" if !$boardroot_url;
			
			# Do the actual query that loads all and comments in one gos
			my $sth = Boards::Post->db_Main->prepare_cached('select p.*,b.folder_name as original_board_folder_name, b.board_userid as board_userid,b.title as board_title, u.photo as user_photo, u.user as username from board_posts p left join users u on (p.posted_by=u.userid), boards b '.
				'where p.boardid=b.boardid and p.deleted=0 and '.
				'top_commentid=? '.
				'order by timestamp desc, postid desc');
		
			$sth->execute($post->id);
			
			# First, prepare all the post results (posts and comments) at the same time
			my @tmp_list;
			while(my $b = $sth->fetchrow_hashref)
			{
				my $b = $self->load_post_for_list($b,{board_folder_name => $board_folder_name,can_admin => $can_admin, boardroot_url => $boardroot_url});
				$first_ts = $b->{timestamp};
				push @tmp_list, $b;
			}
			
			my $board = $post->boardid;
			$post_ref = $self->load_post_for_list($post,{board_folder_name => $board->folder_name, can_admin => $can_admin, boardroot_url => $boardroot_url});
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
		my $board_user	= shift || undef; # if specified, assume this is a user's board and add faux posts for orphaned comments
		my @tmp_list = @{$input || []};
		
		my $board = $board_user ? Boards::Board->by_field(board_userid => $board_user) : undef;
		
		# Used to clean up orphaned comments if the parent is deleted
		my $del_sth = Boards::Post->db_Main->prepare_cached('update board_posts set deleted=1 where postid=?',undef,1);
		
		my $tmpl_incs = $controller->config->{tmpl_incs} || {};
						
		my %crossref = map { $_->{postid} => $_ } @tmp_list;
		
		my $ident_mult = AppCore::Common->context->mobile_flag ? $INDENT_MULTIPLIER / 2 : $INDENT_MULTIPLIER; 
					
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
				$data->{indent_css}	= $indent * $ident_mult; # Arbitrary multiplier
				$data->{indent_is_odd}	= $indent % 2 == 0;
				
				# Lookup the top-most post for this comment
				# If its orphaned, we just delete the comment
				my $top_data = $single_post ? $single_post : $crossref{$data->{top_commentid}};
				if(!$top_data)
				{
					#print STDERR "Odd: Orphaned child $data->{postid} - has top commentid $data->{top_commentid} but not in crossref - marking deleted.\n";
					#$del_sth->execute($data->{postid});
					if($board_user)
					{
						my $ext_id = 'user_comment:'.$id;
						my $post = Boards::Post->by_field(external_id => $ext_id);
						if(!$post)
						{
							my $top = Boards::Post->retrieve($data->{top_commentid});
							
							my $tmpl = $self->get_template($controller->config->{user_comment_tmpl} || 'user_comment_story.tmpl');
							$tmpl->param($_ => $data->{$_}) foreach keys %$data;
							if($top)
							{
								$tmpl->param('top_'.$_ => $top->get($_)) foreach $top->columns;
								$tmpl->param('top_user' => $top->posted_by->user) if $top->posted_by && $top->posted_by->id;
								$tmpl->param('top_board_'.$_ => $top->boardid->get($_)) foreach $top->boardid->columns;
							}
							
							$post = Boards::Post->insert({
								external_id	=> $ext_id,
								# Dont set external_source/url so it doesnt show up as external in the template rendering
								boardid		=> $board,
								poster_name	=> $data->{poster_name},
								poster_email	=> $data->{poster_email},
								poster_photo	=> $data->{poster_photo},
								posted_by	=> 0,
								timestamp	=> $data->{timestamp},
								subject		=> $data->{poster_name} . ' commented on '.($top ? $top->poster_name.'\'s Post' : 'Post #'.$data->{top_commentid}),
								text		=> $tmpl->output,
								post_class	=> 'user_comment',
							});
							
							my $fake_it = $self->to_folder_name($post->subject);
							$fake_it = ($fake_it?$fake_it.'_':'').$post->id if Boards::Post->by_field(folder_name => $fake_it);
							
							$post->folder_name($fake_it);
							$post->update;
							
							print STDERR "Created user comment story from comment $data->{postid} - new story postid is $post\n"; 
						}
						
						#$data->{$_} = $post->get($_) foreach $post->columns;
						my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($self->config->{admin_acl});
						my $data = $controller->load_post_for_list($post,{board_folder_name => $post->boardid->folder_name, can_admin => $can_admin, boardroot_url => $board->boardroot_url});
						foreach my $key (keys %$tmpl_incs)
						{
							$data->{'tmpl_inc_'.$key} = $tmpl_incs->{$key};
						}
						
						push @list, $data;
					}
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
		# ordered by timestamp - so here we batch the kids by their parent then re-flatten the list out to a simple 2d list
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
		#print STDERR "guess_subject: text: [$text]\n";
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
		$req->{bot_trap} = $req->{age123} if $req->{age123};
		if($self->is_spam($req->{comment}, $req->{bot_trap}))
		{
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}

		if($req->{subject} =~ /(http:\/\/|url=)/)
                {
                        $self->log_spam($req->{subject},'subj-url');
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
		
		my $post_class = $req->{post_class};
		foreach my $provider (@VideoProviders)
		{
			eval
			{
				my $config = $provider->controller->config;
				my $rx = $config->{url_regex};
				my ($url) = $req->{comment} =~ /$rx/;
				if($url)
				{
					$post_class = "video";
					last;
				}
			};
			warn "Problem processing with Video Provider ID $provider: $@" if $@;
		}
		
		$req->{attach} = $req->{'attach[]'} if $req->{'attach[]'} && !$req->{attach};
		
		if(!$post_class && 
		    ($req->{comment} =~ /\.(jpg|gif|png)/i ||
		     $req->{attach}  =~ /\.(jpg|gif|png)/i))
		{
			$post_class = "photo";
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
			system_content		=> $req->{system_content} || !$req->{comment},
		});
		
		#print STDERR "Debug: Req:".Dumper($req);
# 		open(TMP,">/tmp/log.txt");
# 		print TMP Dumper($req);
# 		close(TMP);
		
		
		if($req->{attach})
		{
			my @multi_attach = split /\0/, $req->{attach};
			
			#print STDERR "Attachment list: ".Dumper(\@multi_attach);
			$req->{attach} = $multi_attach[0] if @multi_attach > 1;
			undef $@;
			eval {
				my $attach_data = decode_json($req->{attach});
				my $d = $post->data;
				$d->set($_, $attach_data->{$_}) foreach qw(
					picture
					link
					name
					caption
					message
					description
					icon
				);
				$d->set('has_attach', 1);
				
				if(@multi_attach > 1)
				{
					my @parsed = map { decode_json($_) } @multi_attach;
					$d->set('attach_list', \@parsed);
					$d->set('has_multi_attach', 1);
				}
				
				$d->update;
				$post->update;
				
				#print STDERR "Final Dataset: ".Dumper($d);
			};
			
			warn "Error storing attach json data: $@\n" if $@;
			
			#print STDERR "[XTRADAT] \$post after data apply:".Dumper($post) if $self->{debug_extra_data};
			
			# Rather hackish, but it works. 
			if($post->data->get('link') =~/upload/ 
			   && $post->post_class eq 'photo' 
			   && $post->system_content # no comment
			   && $post->data->get('description')) 
			{
				$post->text($post->data->get('description'));
				$post->subject($self->guess_subject($post->text));
				
				if(my $other = Boards::Post->by_field(folder_name => $fake_it))
				{
					$append_flag = 1;
				}
				
				$post->system_content(0);
				$post->update;
			}
		}
		
		# Hack?
		$post->{extra_data} = $post->extra_data;
		
		#print STDERR "[XTRADAT] \$post and {extra_data} prior to folder name check:".Dumper($post,$post->extra_data) if $self->{debug_extra_data};
		
		#if($append_flag)
		if($append_flag || !$post->folder_name || !$post->text)
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
		
		#die Dumper $folder_name,$req, $req->page_path."", $self->binpath."";
		
		#my ($section_name,$folder_name,$board_folder_name,$skin,$r,$page,$req,$path) = @_;
		
		#print STDERR "\$section_name=$section_name,\$folder_name=$folder_name,\$board_folder_name=$board_folder_name\n";
		
		my $post = Boards::Post->by_field(folder_name => $folder_name);
		$post = Boards::Post->retrieve($folder_name) if !$post;
		if(!$post || $post->deleted)
		{
			return $r->error("No Such Post","Sorry, the post folder name you gave did not match any existing Bulletin Board posts. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		my $bin = $self->binpath;
		
		my $board             = $post->boardid;
		my $board_folder_name = $board->folder_name;
		my $boardroot_url     = $board->boardroot_url ? $board->boardroot_url : "$bin/$board_folder_name";
		
		my $sub_page = $req->shift_path;
		
		my $page_path = $req->page_path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		if($sub_page eq 'post')
		{
			my $comment     = $controller->create_new_comment($board,$post,$req);
			my $comment_url = "$page_path#c" . $comment->id;
			
			$controller->send_notifications('new_comment',$comment);
			
			print STDERR __PACKAGE__."::post_page($post): Posted reply ID $comment to post ID $post\n";
			
			if($req->output_fmt eq 'json')
			{
				my $output = $controller->load_post_for_list($comment,{board_folder_name => $board->folder_name, boardroot_url => $boardroot_url});
				
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
			
			$tmpl->param(post_url => "$page_path/post");
			
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
				return $r->redirect($page_path);
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
				return $r->redirect($page_path);
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
				return $r->redirect($page_path);
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
			
			$tmpl->param(post_url => "$page_path/save");
			$tmpl->param(delete_url => "$page_path/delete");
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			$view->breadcrumb_list->push('Edit Post',"$page_path/edit",0);
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
#			my @list = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
#			@list = (AppCore::Config->get("WEBMASTER_EMAIL")) if !@list;
# 			AppCore::EmailQueue->send_email([@list],"[AppCore::Config->get("WEBSITE_NAME")] Post Edited: '".$post->subject."' in forum '".$board->title."'",$email_body);
		
			if($req->output_fmt eq 'json')
			{
				my $json = encode_json({status=>'ok'});
				#return $r->output_data("application/json", $json);
				return $r->output_data("application/json", $json);
			}
			else
			{
				# TODO this could cause problems with subclasses ...
				my $url = "$bin/$board_folder_name/".$post->folder_name;
				#die Dumper $url;
				$r->redirect($url);
			}
				
		}
		else
		{
			if($sub_page && $controller->subpage_action_hook($sub_page, $req, $r, $post))
                        {
                                return $r;
                        }
		
	
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
				# TODO This could cause problems with subclasses ...
				$r->redirect("$bin/$board_folder_name/".$post->top_commentid->folder_name."#c".$post->id);
			}
			
			#sub load_post#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			my $dont_inc_comments = $req->no_comments == 1;
			my $post_resultset = $controller->load_post($post,0,undef,$dont_inc_comments);
			
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
				$view->breadcrumb_list->push($board->title,"$bin/".$board->folder_name,0); # TODO This could cause problems with subclasses
				$view->breadcrumb_list->push($post->subject,$page_path,0);
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
		
		#print STDERR "[DEBUG] ${self}->send_notifications: action:'$action', object:'$object', args:".Dumper($args)."\n"; 
		
		# Actions:
		# - new_post ($post_ref)
		# - new_comment ($comment_ref, $comment_url)
		# - new_like ($like_ref, $noun)
		
		my @notification_methods = @{ $self->config->{notification_methods} || [qw/notify_via_email notify_via_facebook/] };
		
		my @errors;
		foreach my $method (@notification_methods)
		{
			undef $!;
			#print STDERR "[DEBUG] ${self}->send_notifications: action:'$action': Running method '$method'\n";
			push @errors, "$method: $!" if !$self->$method($action, $object, $args);
			if($!)
			{
				print STDERR "[DEBUG] ${self}->send_notifications: action:'$action': Error running '$method': $!\n";
			}
		}
		return @errors;
	}
	
	sub facebook_notify_hook
	{
		# NOOP
	}
	
	sub notify_via_facebook
	{
		my $self = shift;
		my $action = shift;
		my $post = shift;
		my $args = shift;
		
		#print STDERR "[DEBUG] ${self}->notify_via_facebook: action:'$action', post:'$post'\n";
		
		$! = 'Config false or Not a Post or Board Sync Not Enabled or User Said No FB' and return 0 if !AppCore::Config->get('BOARDS_ENABLE_FB_NOTIFY') || ($post->isa('Boards::Post') && (!$post->boardid->fb_sync_enabled || $post->data->get('user_said_no_fb')));
		
		if($action eq 'new_post' ||
		   $action eq 'new_comment')
		{
			my $really_upload = $args->{really_upload} || 0;
		
			if(!$really_upload)
			{
				#print STDERR "[DEBUG] ${self}->notify_via_facebook: action:'$action': Not Really Upload, setting data on post, returning 1\n";
				# Flag this post object for later processing by boards_fb_poller
				$post->data->set('needs_uploaded',1);
				$post->data->update;
				$post->update;
				
				#print STDERR "[DEBUG] ${self}->notify_via_facebook: action:'$action': flag: ".$post->data->get('needs_uploaded')."\n";
				return 1;
			}
			
			#print STDERR "[DEBUG] ${self}->notify_via_facebook: action:'$action': Really upload\n";
			
			
			require LWP::UserAgent;
 			require LWP::Simple;
 
			my $board = $args->{board} || $post->boardid;
			
			my $fb_feed_id	    = $board->fb_feed_id;
			my $fb_access_token = $board->fb_access_token;
			
			if(!$fb_feed_id || !$fb_access_token)
			{
				$! = "Unable to post notification for post# $post to Facebook - Feed ID or Access Token not found.";
				print STDERR "$!\n";
				return 0;
			}
				
			my $ua = LWP::UserAgent->new;
			#$ua->env_proxy;
			
			my $board_folder = $post->boardid->folder_name;
			
			my $folder_name = $post->folder_name;
			my $board = $post->boardid;
			
			my $abs_url = $self->module_url("$board_folder/$folder_name" . ($action eq 'new_comment' ? "#c".$post->id:""),1);
			my $short_abs_url = AppCore::Config->get("BOARDS_ENABLE_TINYURL_SHORTNER") ? LWP::Simple::get("http://tinyurl.com/api-create.php?url=${abs_url}") : $abs_url;
			
			my $short_len = AppCore::Config->get("BOARDS_SHORT_TEXT_LENGTH")     || $SHORT_TEXT_LENGTH;
			my $short = AppCore::Web::Common->html2text($post->text);
			
			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
			
			my $quote = "". #"\"".
				 substr($short,0,$short_len) . #"\"" .
				(length($short) > $short_len ? '...' : '');
				
# 			my $message = $action eq 'new_post' ?
# 				"A new post was added by ".$post->poster_name." in ".$board->title." at $short_abs_url: $quote" :
# 				$post->poster_name.
# 				($post->parent_commentid && $post->parent_commentid->id ? " replied to ".$post->parent_commentid->poster_name : " commented ").
# 				" on \"".$post->top_commentid->subject."\" at $short_abs_url: $quote";

			my $website_noun = AppCore::Config->get('WEBSITE_NOUN') || 'Original Website';
				
			my $form;
			my $notify_url;
			
			if($action eq 'new_post' || ($action eq 'new_comment' && $post->top_commentid && $post->top_commentid->id && !$post->top_commentid->external_id  ))
			{
				# Post new posts OR comments who's parent was not put on FB as new posts
				$notify_url = "https://graph.facebook.com/${fb_feed_id}/feed";
				print STDERR "Posting $action to Facebook URL $notify_url\n";
			
				my $message = $action eq 'new_post' ?
					#$post->poster_name.": $quote - read more at $short_abs_url in '".$board->title."'":
					($post->poster_name eq 'Pleasant Hill Church' ? '': $post->poster_name.': ') .
						"$quote - read more at $short_abs_url in '".$board->title."'":
					($post->poster_name.": $quote - ".
						($post->parent_commentid && $post->parent_commentid->id && $post->parent_commentid->poster_name ne $post->poster_name ? " replied to ".$post->parent_commentid->poster_name : " commented ").
						" on \"".$post->top_commentid->subject."\" at $short_abs_url");
				
				my $photo = $post->poster_photo ? $post->poster_photo :
					$post->posted_by ? $post->posted_by->photo : "";
				$photo = AppCore::Config->get("WEBSITE_SERVER") . $photo if $photo =~ /\//;
				
				$form = 
				{
					access_token	=> $fb_access_token,
					message		=> $message,
					link		=> $abs_url,
					picture		=> $post->data->get('picture') ? $post->data->get('picture') : $photo,
					name		=> $post->subject,
					caption		=> $action eq 'new_post' ? 
						"by ".$post->poster_name." in ".$board->title :
						"by ".$post->poster_name." on '".$post->top_commentid->subject."' in ".$board->title,
					description	=> $short_text,
					actions		=> qq|{"name": "View on $website_noun", "link": "$abs_url"}|,
				};
			}
			else #if($action eq 'new_comment')
			{
				$notify_url = "https://graph.facebook.com/". $post->top_commentid->external_id ."/comments";
				print STDERR "Posting New Comment to Facebook URL $notify_url\n";
				
				my $message = ($post->posted_by && $post->posted_by->id && $post->posted_by->fb_userid eq $board->fb_feed_id) ?
							$short :
							$post->poster_name . ": $quote - " . 
								($post->parent_commentid && 
								 $post->parent_commentid->id && 
								 $post->parent_commentid->poster_name ne $post->poster_name ? " replied to ".$post->parent_commentid->poster_name : " commented ").
								" on \"".$post->top_commentid->subject."\" at $short_abs_url";
				
				$form = 
				{
					access_token	=> $fb_access_token,
					message		=> $message,
					actions		=> qq|{"name": "View on $website_noun", "link": "$abs_url"}|,
				};
			
			}
			
			$form->{picture} = AppCore::Config->get('WEBSITE_SERVER') . $form->{picture} if $form->{picture} && $form->{picture} !~ /^https?:/;
			
			my $hook_object = $args->{hook} || $self;
			
			$hook_object->facebook_notify_hook($post, $form, 
			{
				action => $action,
				abs_url => $abs_url,
				short_abs_url => $short_abs_url,
				short_text => $short_text,
				quote => $quote,
			});
			
			use Data::Dumper;
			print STDERR "Facebook post data: ".Dumper($form);
			#die "[DEBUG] Facebook post data: ".Dumper($form);
			
			my $response = $ua->post($notify_url, $form);
			undef $@;
			if ($response->is_success) 
			{
				my $rs = decode_json($response->decoded_content);
				$post->external_id($rs->{id});
				$post->update;
				
				print STDERR "Facebook post successful, Facebook Post ID: ".$post->external_id.", internal postid: $post\n";
			}
			else 
			{
				print STDERR "ERROR Posting to facebook, message: ".$response->status_line."\nAs String:".$response->as_string."\n";
				$@ = 'Error uploading to facebook: '.$response->as_string;
				return 0; 
			}
			
			return 1;
		}
		
		#print STDERR "[DEBUG] ${self}->notify_via_facebook: Action '$action' not handled\n";
		
		$! = 'FB Action \''.$action.'\' Not Handled';
		return 0;
	}
	
	sub email_new_post
	{
# 			print STDERR __PACKAGE__."::email_new_post(): Disabled till email is enabled\n";
# 			return;
			
		my $self = shift;
		my $post = shift;
		my $args = shift;
		
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		
		my $board_folder = $post->boardid->folder_name;
		
		my $folder_name = $post->folder_name;
		my $board = $post->boardid;
		
		my $abs_url = $self->module_url("$board_folder/$folder_name",1);
		
		my $email_body = qq{A new post was added by }.$post->poster_name." in forum '".$board->title.qq{':

    }.AppCore::Web::Common->html2text($post->text).qq{

Here's a link to that page: 
    $abs_url
    
Cheers!};
			
		my @list = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
		@list = (AppCore::Config->get("WEBMASTER_EMAIL")) if !@list;
		
		# Dont email the person that just posted this :-)
		@list = grep { $_ ne $post->poster_email } @list;
		
		AppCore::EmailQueue->send_email([@list],"[".AppCore::Config->get("WEBSITE_NAME")."] ".$post->poster_name." posted in '".$board->title."'",$email_body) if @list;
	}
	
	sub replace_lkey
	{
		my $text = shift;
		my $user_ref = shift;
		return $text if !$user_ref || !$user_ref->id;
		my $id = $user_ref->get_lkey(); #$user_ref->id + 3729;
		$text =~ s/lkey=[A-Za-z0-9+\/]+?/lkey=$id/g;
		return $text;
	}
	
	sub email_new_comment
	{
		my $self = shift;
		my $post = shift;
		my $args = shift;
		
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		
#		print STDERR __PACKAGE__."::email_new_post_comments(): Disabled till email is enabled\n";
# 			return;
		
		my $comment = $post;
		my $comment_url = $args->{comment_url} || $self->binpath ."/". $comment->boardid->folder_name . "/". $comment->top_commentid->folder_name."?lkey=0#c" . $comment->id;
		
		my $server = 
		my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.AppCore::Web::Common->html2text($comment->text).qq{

Here's a link to that page: 
    ${server}$comment_url
    
Cheers!};
		#
		AppCore::EmailQueue->reset_was_emailed;
		
		my $noun = $self->config->{long_noun} || 'Bulletin Boards';
		my $title = AppCore::Config->get("WEBSITE_NAME"); 
		
		my @list = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
		@list = (AppCore::Config->get("WEBMASTER_EMAIL")) if !@list;
		
		my $email_subject = "[$title] ".$comment->poster_name." commented on '".$comment->top_commentid->subject."'";
		
		# Dont email the person that just posted this :-)
		@list = grep { $_ ne $comment->poster_email } @list;
		
		AppCore::EmailQueue->send_email([@list],$email_subject,$email_body);
		
		AppCore::EmailQueue->send_email([$comment->parent_commentid->poster_email],$email_subject,replace_lkey($email_body,$comment->parent_commentid->posted_by))
				if $comment->parent_commentid && 
				$comment->parent_commentid->id && 
				$comment->parent_commentid->poster_email &&
				$comment->parent_commentid->poster_email ne $comment->poster_email && 
				!AppCore::EmailQueue->was_emailed($comment->top_commentid->poster_email);
		
		AppCore::EmailQueue->send_email([$comment->top_commentid->poster_email],$email_subject,replace_lkey($email_body,$comment->top_commentid->posted_by))
				if $comment->top_commentid && 
				$comment->top_commentid->id && 
				$comment->top_commentid->poster_email &&
				$comment->top_commentid->poster_email ne $comment->poster_email &&  
				!AppCore::EmailQueue->was_emailed($comment->top_commentid->poster_email);
		
		my $board = $comment->boardid;
		eval {
		AppCore::EmailQueue->send_email([$board->managerid->email],$email_subject,replace_lkey($email_body,$comment->managerid))
					if $board && 
					$board->id && 
					$board->managerid && 
					$board->managerid->id && 
					$board->managerid->email && 
					$board->managerid->email ne $comment->poster_email &&
					!AppCore::EmailQueue->was_emailed($board->managerid->email);
		};			
		AppCore::EmailQueue->reset_was_emailed;
	}
	
	sub email_new_like
	{
		my $self = shift;
		my $post = shift;
		my $args = shift;
		
		my $like = $post;
		my $noun = $args->{noun};
		
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		
		my $comment_url = join('/', $self->binpath, $like->postid->boardid->folder_name, $like->postid->folder_name)."?lkey=0#c" . $like->postid->id;
		
		AppCore::EmailQueue->reset_was_emailed;
		
		my $noun = $self->config->{long_noun} || 'Bulletin Boards';
		my $title = AppCore::Config->get('WEBSITE_NAME'); 
		
		# Notify User
		my $email_subject = "[$title $noun] ".($like->name?$like->name:'Anonymous')." likes your $noun '".$like->postid->subject."'";
		my $email_body = $like->name." likes your $noun '".$like->postid->subject."\n\n\t".
				AppCore::Web::Common->html2text($like->postid->text)."\n\n".
				"Here's a link to that page:\n".
				"\t${server}$comment_url\n\n".
				"Cheers!";
		
		my $user = AppCore::Common->context->user;
		
		AppCore::EmailQueue->send_email($like->postid->poster_email,$email_subject,replace_lkey($email_body,$like->postid->posted_by)) unless $like->postid->poster_email =~ /example\.com$/ || ($user && $user->email eq $like->postid->poster_email);
		
		# Notify Webmaster
		my @list = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
		@list = (AppCore::Config->get('WEBMASTER_EMAIL')) if !@list;
		
		$email_subject = "[$title $noun] ".($like->name?$like->name:'Anonymous')." likes ".$like->postid->poster_name."'s $noun '".$like->postid->subject."'";
		$email_body = $like->name." likes ".$like->postid->poster_name."'s $noun '".$like->postid->subject."\n\n\t".
				AppCore::Web::Common->html2text($like->postid->text)."\n\n".
				"Here's a link to that page:\n".
				"\t${server}$comment_url\n\n".
				"Cheers!";
		
		# Dont email the person that just posted this :-)
		if($user)
		{
			@list = grep { $_ ne $user->email} @list;
		}
		AppCore::EmailQueue->send_email([@list],$email_subject,$email_body);
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
			$self->email_new_post($post,$args);
			return 1;
		}
		elsif($action eq 'new_comment')
		{
 			$self->email_new_comment($post,$args);
			return 1;
		}
		elsif($action eq 'new_like')
		{
			$self->email_new_like($post,$args);
			return 1;
		}
		
		$! = "Email action '$action' not handled";
		return 0;
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
			ip_address	=> $ENV{REMOTE_ADDR},
			user_agent	=> $ENV{HTTP_USER_AGENT},
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
		return 0 if $SPAM_OVERRIDE || $ENV{SPAM_OVERRIDE} || ($user && ($user->check_acl($self->config->{admin_acl}) || $user->email eq 'susan.bryan5@gmail.com'));
		
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
			if($weight >= 10)
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
			$text =~ /link=/) ||
			$text =~ /\[[uU][rR][lL]/) # faster than /i
		{
			#print STDERR "Debug Rejection: comment='$comment', commentor='$commentor'\n";
			#die "Sorry, you sound like a spam bot - go away. ($req->{comment})" if !$SPAM_OVERRIDE;
			$self->log_spam($text,'links');
			$@ = "Links aren't allowed, sorry";
			return 1;
		}

		### Method: One 'http:' per post if not a logged-inuser
		if(
			(!$user || !$user->id))
		{
			my @link_count = $text =~ /(http:)/g;
			if(@link_count > 1)
			{
				$self->log_spam($text,'multi-http-intext');
				$@ = "More than one textual URL not allowed, sorry";
				return 1;
			}
		}
		
		### Method: 'Russian' - Ban russian characters
		if($text =~/[итпрогамскюедвеь�]/)
		{
			$self->log_spam($text,'russian');
			$@ = "Please use only Engish on this website";
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
		
		$req->{bot_trap} = $req->{age123} if $req->{age123};
		
		if($self->is_spam($req->{comment}, $req->{bot_trap}))
		{
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}

		if($req->{subject} =~ /(http:\/\/|url=)/)
		{
			$self->log_spam($req->{subject},'subj-url');
			AppCore::Web::Common::redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		if(!$req->{subject})
		{
			#my $text = AppCore::Web::Common->html2text($req->{comment});
			#$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
			$req->{subject} = $self->guess_subject($req->{comment});
		}
		
		my $fake_it = $self->to_folder_name($req->{subject});
		$fake_it =~ s/(^\s+|\s+$)//g;

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
		
		if($append_flag || !$comment->folder_name || !$comment->text)
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

		if($req->{subject} =~ /(http:\/\/|url=)/)
                {
                        $self->log_spam($req->{subject},'subj-url');
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
