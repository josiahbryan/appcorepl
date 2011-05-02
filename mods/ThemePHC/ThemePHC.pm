use strict;

package ThemePHC;
{
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	use Scalar::Util 'blessed';

	__PACKAGE__->register_theme('PHC 2011','Pleasant Hill Church 2011 Website Update', [qw/home admin sub mobile/]);

	
	# The output() routine is the core of the Theme - it's where the theme applies the
	# data from the Content::Page object and any optional $parameters given
	# to the HTML template and sends the template out to the browser.
	# The template chosen is (should be) based on the $view_code requested by the controller.
	sub output
	{
		my $self       = shift;
		my $page_obj   = shift || undef;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $parameters = shift || {};
		
		my $tmpl = undef;
		#print STDERR __PACKAGE__."::output: view_code: '$view_code'\n";
		
		my $pref = AppCore::Web::Common::getcookie('mobile.sitepref');
		$view_code = 'mobile' if $pref eq 'mobile';
		
		if($view_code eq 'home')
		{
			$tmpl = $self->load_template('frontpage.tmpl');
		}
		elsif($view_code eq 'admin')
		{
			$tmpl = $self->load_template('admin.tmpl');
		}
		elsif($view_code eq 'mobile')
		{
			$tmpl = $self->load_template('mobile.tmpl');
		}
		# Don't test for 'sub' now because we just want all unsupported view codees to fall thru to subpage
		#elsif($view_code eq 'sub')
		else
		{
			$tmpl = $self->load_template('subpage.tmpl');
		}
		
		## Add other supported view codes
			
		$self->auto_apply_params($tmpl,$page_obj);
		
		#print STDERR AppCore::Common::get_stack_trace();
			
		#$r->output($page_obj->content);
		$r->output($tmpl); #->output);
	};
	
	sub remap_template
	{
 		my $class = shift;
 		my $requesting_package = shift;
 		my $requested_theme_file = shift;
 		#print STDERR __PACKAGE__."::remap_template(): $requesting_package wants '$requested_theme_file'\n"; 
		return undef; 
	}
	
	sub remap_url
	{
 		my $class = shift;
 		my $url = shift;
 		#print STDERR __PACKAGE__."::remap_url(): Accessing '$url'\n";
 		
#  		if(AppCore::Common->context->mobile_flag)
#  		{
# 			if($url eq '/contact')
# 			{
# 				return '/m/contact';
# 			}
# 			elsif($url eq '/')
# 			{
# 				return '/m';
# 			}
# 		}
# 		else
# 		{
#  			if($url eq '/m/contact')
# 			{
# 				return '/contact';
# 			}
# 			elsif($url eq '/m')
# 			{
# 				return '/';
# 			}
# 		}
		return undef;
	}
	
};
1;
