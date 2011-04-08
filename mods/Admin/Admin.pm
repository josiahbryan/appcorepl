use strict;
package Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	# Use this to access Content::Page::Controller
	use Content::Page;
	
	use AppCore::User;
	use AppCore::AuthUtil;
	
	sub new { bless {}, shift }
	
	#my $PAGE_ROOT = 'pages';
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		
	/);
	
	#pages
	
	sub main
	{
		my ($self,$req) = shift;
		
		AppCore::Web::Common->redirect("/content/admin");
	}
	
# 	sub pages
# 	{
# 		my ($self,$req) = @_;
# 		
# 		AppCore::AuthUtil->require_auth(['ADMIN']);
# 		
# 		return $self->dispatch($req, 'Admin::Pages');
# 	}
	
};

1;
