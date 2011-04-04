use strict;

package ThemeBasic;
{
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	
=head1 View Code Documentation
	
	Currently Used View Codes:
	
		- 'User' Module:
			login
			signup
			forgot_pass
		- 'Content' Module:
			Default Page Type:
				default
			
=cut
	
	
	
	# The output() routine is the core of the Theme - it's where the theme applies the
	# data from the Content::Page object and any optional $parameters given
	# to the HTML template and sends the template out to the browser.
	# The template chosen is (should be) based on the $view_code requested by the controller.
	sub output
	{
		my $self       = shift;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $page_obj   = shift || undef;
		my $parameters = shift || {};
		
		# ThemeEngine::load_template() assumes the file your asking file is in your 'tmpl/' folder in this module
		my $tmpl = $self->load_template('basic.tmpl');
		if($page_obj)
		{
			$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
		}
		
		# load_template() automatically adds this template parameter in to your template:
		#$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', __PACKAGE__));
		
		#$r->output($page_obj->content);
		$r->output($tmpl->output);
	};
	
};
1;