# Custom controller for the Pastors Blog 
package ThemePHC::PastorsBlog;
{
	use AppCore::Web::Common;
	use AppCore::Common;
	use AppCore::EmailQueue;
	use Boards;
	
	use strict;
	
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	# Contains all the data packages we need, such as Boards::Post, etc
	use Boards::Data;
	
	# Register our pagetype
	#__PACKAGE__->register_controller('PHC Talk Board','PHC Prayer/Praise/Talk Page',1,0);  # 1 = uses page path,  0 = doesnt use content
	
	# Register our controller-specific notifications
	# TODO: Should we list the module as 'Boards' or as our own ThemePHC::BoardsTalk ...? For now, leaving as boards till pref UI is implemented.
	our $PREF_EMAIL_NEW_POST = AppCore::User::PrefOption->register('ThemePHC::PastorsBlog', 'Pastor\'s Blog', 'Send me an email for new Pastor\'s Blogs', {default_value=>1});
	
	# This will allow the 'PrefOption' module to remove any preferences for the section/subsection that have not already been seen
	AppCore::User::PrefOption->clear_old_prefs('ThemePHC::PastorsBlog', 'Pastor\'s Blog');
	
	my $PASTOR_ACL = [qw/Pastor/];
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config({
			
			list_length => 3, # nbr of posts to load initially and when paging
			
			#new_post_tmpl	=> 'prayer/new_post.tmpl',
			tmpl_incs 	=> 
			{
				newpost	=> 'inc-newpostform-pastorsblog.tmpl',
				postrow => 'inc-postrow-pastorsblog.tmpl',	
			},
		});
		
		return $self;
	};
	
	sub new_post_hook
	{
		my $class = shift;
		my $tmpl = shift;
		#die "new post hook";
		my $can_post = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($PASTOR_ACL);
		$tmpl->param(can_post=>$can_post);
	}
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;
		my $user = shift;
		
		my $cmt = $req->{comment};
		
		
		$cmt =~ s/(^\s+|\s+$)//g;
		$cmt =~ s/(^&nbsp;)//g;
		$cmt =~ s/<p>&nbsp;/<p>/g;
		$cmt =~ s/<p>&nbsp;<\/p>//g;
		$cmt =~ s/^\s*\n+//sg;
		$cmt =~ s/(^\t+|\t+$)//g;

		#die Dumper $cmt if $cmt =~ /^\s*\n/;
		#die Dumper $cmt;
		#die "Test done";
		
		$req->{comment} = $cmt;
		
# 		open(TMP,">/tmp/test.txt");
# 		print TMP $cmt;
# 		close(TMP); 
# 		
		#die "Test done";
		
		delete $req->{plain_text};
		$req->{no_html_conversion} = 1;
		
		my $can_post = ($_ = AppCore::Web::Common->context->user) && $_->check_acl($PASTOR_ACL);
		die "Unauthorized - sorry, you can't post in this blog" if !$can_post;
		
		
		# Rely on superclass to do the actual post creation
		my $post = $self->SUPER::create_new_thread($board, $req, $user);
		
		# Flag as a 'post' not just a 'small update' 
		$post->post_class('post');
		$post->update;
		
# 		open(TMP,">/tmp/test2.txt");
# 		print TMP $post->text;
# 		close(TMP);
# 		
		$self->send_email_notifications($post);
		
		$self->send_talk_notifications($post);
		
		return $post;
	}
	
	sub send_email_notifications
	{
		my $self = shift;
		my $post = shift;
		
		print STDERR "PastorsBlog::send_email_notifications for new post: ".$post->subject."\n";
		
		my @users = AppCore::User->retrieve_from_sql('email <> ""'); # and allow_email_flag!=0');
		#my @users = AppCore::User->retrieve_from_sql('email like "josiah%" or email like "jbryan%"'); # and allow_email_flag!=0');
		
		
		my $subject = $post->subject; # the subject was set correctly in create_new_thread()
		my $body = AppCore::Web::Common->html2text($post->text);
		$body =~ s/\n\s*$//g;
		
		my $folder = $post->folder_name;
		
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		
		my %seen_email = ();
		foreach my $user (@users)
		{
			if(! $PREF_EMAIL_NEW_POST->value($user) )
			{
				print STDERR "Not emailing ".$user->email." due to negative preference on prefid ".$PREF_EMAIL_NEW_POST." for userid $user\n";
				next;
			}
			
			next if index($user->email,'@') < 0;
			
			my $subj = "Pastor Bryan Added a New Post in the Pastor's Blog";
			my $text = "Hi ".$user->display.",\n"
				."\n"
				."Pastor Bryan has added a new post to the \"Pastor's Blog\" at MyPleasantHillChurch.org.\n"
				."\n"
				."Read \"".$post->subject."\" here:\n"
				."    ${server}/learn/pastors_blog/$folder?lkey=".($user->get_lkey())."\n"
				."\n"
				."Thanks,\n"
				."The PHC Website Robot";
				
			
			if(!$seen_email{$user->email})
			{
				#PHC::Web::Common->send_email([$user->email], $subj, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
				my $msgid = AppCore::EmailQueue->send_email([$user->email], $subject, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
				
				print STDERR "Queued msgid $msgid ".$user->email."\n"; #Subject: $subj\n$text\n";
			
				
				$seen_email{$user->email} = 1;
			}
		}
		
		#AppCore::Web::Common->send_email(\@emails, $subject, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
	}
	
	sub send_talk_notifications
	{
		my $self = shift;
		my $post = shift;
		
		my $folder = $post->folder_name;
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		my $post_url = "${server}/learn/pastors_blog/$folder";
		
		my $data = {
			poster_name	=> 'PHC Website',
			poster_photo	=> 'https://graph.facebook.com/180929095286122/picture', # Picture for PHC FB Page
			poster_email	=> 'josiahbryan@gmail.com',
			comment		=> "Pastor Bryan has added a new post, \"".$post->subject."\" to the \"Pastor's Blog\". Read it at: $post_url",
			subject		=> "New Pastor's Blog: '".$post->subject."'", 
		};
		
		my $talk_board_controller = AppCore::Web::Module->bootstrap('ThemePHC::BoardsTalk');
		my $talk_board = Boards::Board->retrieve(1); # id 1 is the prayer/praise/talk board
		
		my $talk_post = $talk_board_controller->create_new_thread($talk_board,$data);
		
		# Add extra data internally
		$talk_post->data->set('blog_postid',$post->id);
		$talk_post->data->set('post_url',$post_url);
		$talk_post->data->set('title',$post->subject);
		$talk_post->data->update;
		$talk_post->update;
		$talk_post->{_orig} = $post;
		
		# Note: We call send_notifcations() on $self so it will call our facebook_notify_hook()
		#       to reformat the FB story args the way we want them before uploading instead 
		#       of using the default story format.
		#     - We 'really_upload' so we can use $self (because we want to call our facebook_notify_hook())
		#     - Give the $talk_board in the args because the FB notification routine needs the
		#       FB wall ID and sync info from the board - and its not set on the Pastor's Blog board
		my @errors = $self->send_notifications('new_post',$talk_post,{really_upload=>1, board=>$talk_board}); # Force the FB method to upload now rather than wait for the poller crontab script
		if(@errors)
		{
			print STDERR "Error sending notifications of new blog post $post: \n\t".join("\n\t",@errors)."\n";
		}
			
	}
	
	sub facebook_notify_hook
	{
		my $self = shift;
		my $post = shift;
		my $form = shift;
		my $args = shift;
		
		# Create the body of the FB post
		my $post_url = $post->data->get('post_url');
		
		$form->{message} = $post->text; 
		#"New video from PHC: ".$post->data->get('description').". Watch it now at ".LWP::Simple::get("http://tinyurl.com/api-create.php?url=${phc_video_url}");
		 
		# Set the URL for the link attachment
		$form->{link} = $post_url;
		
		#my $image = $self->video_thumbnail($post);
		
		#my $pastor_user = AppCore::User->by_field(email => 'pastor@mypleasanthillchurch.org');
		
		my $orig_post = $post->{_orig};
		my $quote;
		if(!$orig_post)
		{
			$quote = "Read the full post at ".$post_url;
		}
		else
		{
			our $SHORT_TEXT_LENGTH = 60;
			my $short_len = AppCore::Config->get("BOARDS_SHORT_TEXT_LENGTH")     || $SHORT_TEXT_LENGTH;
			my $short = AppCore::Web::Common->html2text($orig_post->text);
			
			my $short_text  = substr($short,0,$short_len) . (length($short) > $short_len ? '...' : '');
			
			$quote = "\"".
				 substr($short,0,$short_len) . "\"" .
				(length($short) > $short_len ? '...' : '');
		}
		
		my $image = 'http://cdn1.mypleasanthillchurch.org/appcore/mods/User/user_photos/user68813c307218b849d02d2595c96e51e7.jpg'; # Pastors photo
		
		# Finish setting link attachment attributes for the FB post
		$form->{picture}	= $image; # ? $image : 'https://graph.facebook.com/180929095286122/picture';
		$form->{name}		= $post->data->get('title');
		$form->{caption}	= "by Pastor Bruce Bryan";
		$form->{description}	= $quote; 
		#$post->data->get('description');
		
		# Update original post with attachment data
		my $d = $post->data;
		$d->set('has_attach',1);
		$d->set('name', $form->{name});
		$d->set('caption', $form->{caption});
		$d->set('description', $form->{description});
		$d->set('picture', $form->{picture});
		$d->update;
		$post->post_class('link');
		$post->update;
		
		# Replace the default Boards FB action with a link to the video post
		$form->{actions} = qq|{"name": "View at PHC's Site", "link": "$post_url"}|;
		
		# 
		
		# We're working with a hashref here, so no need to return anything, but we will anyway for good practice
		return $form;
	}

};
1;
