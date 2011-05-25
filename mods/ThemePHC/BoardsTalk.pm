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
	__PACKAGE__->register_controller('PHC Talk Board','PHC Prayer/Praise/Talk Page',1,0);  # 1 = uses page path,  0 = doesnt use content
	
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
		
		# Store the tag in the ticker_class member for easy access in the template rendering
		my $tag = $req->{tag} || 'talk';
		$post->ticker_class($tag);
		$post->update;
	}
	
};
1;
