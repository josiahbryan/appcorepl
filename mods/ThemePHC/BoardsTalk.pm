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
	our $PREF_EMAIL_PRAISE = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Praise" posts');
	our $PREF_EMAIL_PRAYER = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Prayer Requests" posts');
	our $PREF_EMAIL_TALK   = AppCore::User::PrefOption->register('Boards', 'Prayer/Praise/Talk Notifications', 'Dont send me an email for every new post, but do send me an email for new "Just Talking" posts');
	
	my $EPA_ACL = [qw/Pastor/];
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config({
			
			new_post_tmpl	=> 'prayer/new_post.tmpl',
			tmpl_incs 	=> 
			{
				newpost	=> 'inc-newpostform-talkpage.tmpl',
				postrow => 'inc-postrow-talkpage.tmpl',	
			},
		});
		
		return $self;
	};
	
	sub create_new_thread
	{
		my $self = shift;
		my $board = shift;
		my $req = shift;
		my $user = shift;
	
		my $post = $self->SUPER::create_new_thread($board, $req, $user);
		
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
		
		# Store the tag in the ticker_class member for easy access in the template rendering
		$post->ticker_class($tag);
		$post->update;
		
		return $post;
	}
	
};
1;
