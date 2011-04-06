use strict;

package ThemeBasic;
{
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	use Scalar::Util 'blessed';
	
=head1 View Code Documentation
	
	- 'Home' - front page of the wqebsite
	- 'Sub' - website subpage
			
=cut
	
	
	
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
		
		# ThemeEngine::load_template() assumes the file your asking file is in your 'tmpl/' folder in this module
		my $tmpl = $self->load_template('basic.tmpl');
		if(!$self->apply_page_obj($tmpl,$page_obj))
		{
			my $blob = (blessed $page_obj && $page_obj->isa('HTML::Template')) ? $page_obj->output : $page_obj;
			my @titles = $blob=~/<title>(.*?)<\/title>/g;
			#$title = $1 if !$title;
			@titles = grep { !/\$/ } @titles;
			$tmpl->param(page_title => shift @titles);
			$tmpl->param(page_content => $blob);
		}
		
		# load_template() automatically adds this template parameter in to your template:
		#$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', __PACKAGE__));
		
		#$r->output($page_obj->content);
		$r->output($tmpl->output);
	};
	
};
1;