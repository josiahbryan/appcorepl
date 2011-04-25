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
		if($view_code eq 'home')
		{
			$tmpl = $self->load_template('frontpage.tmpl');
		}
		elsif($view_code eq 'admin')
		{
			$tmpl = $self->load_template('admin.tmpl');
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
	
};
1;