use strict;

package ThemeBasic;
{
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	
	## Even though the following routines (new/get_view/output) 
	## are implemented in ThemeEngine, we provide the default implementation
	## here for reference and for example purposes.
	
	__PACKAGE__->register('Basic','Very simple theme - no styling.', [qw/sub/]);
	
	# Themes don't HAVE to provide a new method - if they don't, the output() and get_view()
	# methods will be called on the package using '->' instead of on an instance or instead of using '::'.
	sub new
	{
		bless {}, shift;
	}
	
	# Themes don't have to implement get_view() - only if you have separate sub-classes that
	# implement a specific view code - then you can return that class' instance here based 
	# on the view_code requestyed.
	sub get_view
	{
		my $self = shift;
		my $code = shift;
		$self->{view_code} = $code;
		return $self;
	}
	
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
		
		my $tmpl = AppCore::Web::Common::load_template("mods/ThemeBasic/tmpl/basic.tmpl");
		$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
		$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', __PACKAGE__));
		
		#$r->output($page_obj->content);
		$r->output($tmpl->output);
	};
	
};
1;