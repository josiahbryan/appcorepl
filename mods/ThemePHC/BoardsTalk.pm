# Custom controller for the "prayer/praise/talk" board on the new PHC website
package ThemePHC::BoardsTalk;
{
	use AppCore::Web::Common;
	use AppCore::Common;
	use AppCore::EmailQueue;
	use Boards;
	
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
	our $PREF_EMAIL_PRAISE = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Send me an email for every new "Praise" posts', {default_value=>0});
	our $PREF_EMAIL_PRAYER = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Send me an email for every new "Prayer Requests" posts', {default_value=>1});
	our $PREF_EMAIL_TALK   = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Send me an email for every new "Just Talking" posts', {default_value=>0});
	
	our $PREF_EALERT_PRAISE = AppCore::User::PrefOption->register('Boards', '"e-Alert" Notifications', 'Include my email when sending ePraiseAlerts');
	our $PREF_EALERT_PRAYER = AppCore::User::PrefOption->register('Boards', '"e-Alert" Notifications', 'Include my email when sending ePrayerAlerts');
	our $PREF_EALERT_TALK   = AppCore::User::PrefOption->register('Boards', '"e-Alert" Notifications', 'Include my email when sending eInfoAlerts');
	
	# This will allow the 'PrefOption' module to remove any preferences for the section/subsection that have not already been seen
	AppCore::User::PrefOption->clear_old_prefs('Boards', 'Prayer/Praise/Talk Notifications');
	AppCore::User::PrefOption->clear_old_prefs('Boards', '"e-Alert" Notifications'); 
	
	my $EPA_ACL = [qw/Pastor/];
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config({
			
			#new_post_tmpl	=> 'prayer/new_post.tmpl',
			tmpl_incs 	=> 
			{
				newpost	=> 'inc-newpostform-talkpage.tmpl',
				postrow => 'inc-postrow-talkpage.tmpl',	
			},
		});
		
		return $self;
	};
	
	sub new_post_hook
	{
		my $class = shift;
		my $tmpl = shift;
		#die "new post hook";
		my $can_epa = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($EPA_ACL);
		$tmpl->param(can_epa=>$can_epa);
	}
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;
		my $user = shift;
		
		my $can_epa = 1 if ($_ = AppCore::Web::Common->context->user) && $_->check_acl($EPA_ACL);
		$req->{epa} = 0 if !$can_epa;
		
		# Attempt to guess the type of post based on the text - only if the user didn't specify it manually
		my $tag = $req->{tag} || 'talk';
		if(!$req->{user_clicked_tag})
		{
			if($req->{comment} =~ /(please\s[^\.\!\?]*?)?remember|pray/i)
			{
				$tag = 'pray';
			}
			elsif($req->{comment} =~ /(prais|thank)/i)
			{
				$tag = 'praise';
			}
		}
		
		# If an 'e-alert', then create a dated, nouned subject
		if($req->{epa})
		{
			my $noun = $self->alert_noun($tag);
			my $dt = AppCore::Web::Common::dt_date();
		
			$req->{subject} = $noun.' '.$dt->month.'.'.$dt->day.'.'.substr(''.$dt->year,2,2).': '.$self->guess_subject($req->{comment});
		}
	
		# Rely on superclass to do the actual post creation
		my $post = $self->SUPER::create_new_thread($board, $req, $user);
		
		# Store the tag in the ticker_class member for easy access in the template rendering
		$post->ticker_class($tag);
		$post->update;
		
		$post->ticker_class; # this is required for some reason - otherwise the ajax-post that loads doesnt read the ticker_class - but a full page reload does!
		
		#print STDERR "Assigning ticker class: $tag (".$post->ticker_class.")\n";
		
		# If an e-alert, tag the post with the e-alert tag and the noun, then send the emails
		if($req->{epa})
		{
			my $noun = $self->alert_noun($tag);
			$post->add_tag($noun);
			$post->add_tag('e-alert');
			
			$self->send_email_alert($post);
		}
		
		# TODO Honor user prefs re email notice on specific tags
		
		return $post;
	}
	
	sub send_email_alert
	{
		my $self = shift;
		my $post = shift;
		
		my $tag = lc $post->ticker_class;
		
		if($tag !~ /^(talk|pray|praise)$/)
		{
			print STDERR __PACKAGE__."::send_email_alert(): Unknown ticker class '$tag' - not alerting\n";
		}
		
		my $noun = $self->alert_noun($tag);
		
		# TODO Honor user prefereances re opt outs
		
		my @users = AppCore::User->retrieve_from_sql('email <> ""'); # and allow_email_flag!=0');
		
# 		# Just for Debugging ...
# 		@users = map { AppCore::User->retrieve($_) } qw/1 51/;
		
		# Extract email addresses
		my @emails = map { $_->email } @users;
		
		# Make emails unique (dont send the same email twice to the same user)
		my %unique_map = map { $_ => 1 } @emails;
		@emails = keys %unique_map;
		
		my $subject = $post->subject; # the subject was set correctly in create_new_thread()
		my $body = AppCore::Web::Common->html2text($post->text);
		$body =~ s/\n\s*$//g;
		
		my $folder = $post->folder_name;
		
		my $server = $AppCore::Config->get('WEBSITE_SERVER');
		my $text = "Dear Friends,\n\n".
			$body.
			"\n\nPastor Bryan".
			"\n\n-----\n".qq{

Here's a link to this $noun posted on the PHC Website:
    ${server}/connect/talk/$folder
    
Cheers!
};
		AppCore::Web::Common->send_email(\@emails, $subject, $text, 0, 'Pastor Bruce Bryan <pastor@mypleasanthillchurch.org>');
		
		
	}
	
	sub alert_noun
	{
		my $self = shift;
		
		my $tag = lc shift || 'talk';
		
		my $noun = "e" . 
			($tag eq 'pray'   ? 'Prayer' :
			 $tag eq 'praise' ? 'Praise!' : 'Info') . "Alert";
		
		return $noun;
	}
	
	
};
1;
