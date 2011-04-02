use strict;

package ThemePHC;
{
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	
	# The output() routine is the core of the Theme - it's where the theme applies the
	# data from the Content::Page object and any optional $parameters given
	# to the HTML template and sends the template out to the browser.
	# The template chosen is (should be) based on the $view_code requested by the controller.
	sub output
	{
		my $self = shift;
		my $view_code = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		my $parameters = shift || {};
		
		my $tmpl = AppCore::Web::Common::load_template("mods/ThemePHC/tmpl/frontpage.tmpl");
		$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
		$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', __PACKAGE__));
		
		#$r->output($page_obj->content);
		$r->output($tmpl->output);
	};
	
};
1;