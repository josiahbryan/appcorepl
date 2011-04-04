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
		my $self       = shift;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $page_obj   = shift || undef;
		my $parameters = shift || {};
		
		if($view_code eq 'home')
		{
			my $tmpl = $self->load_template('frontpage.tmpl');
			$r->output($tmpl->output);
		}
		else
		{
			my $tmpl = $self->load_template('subpage.tmpl');
			
			my $sub = undef;
			if($view_code eq 'default')
			{
				# do nothing	
			}
			elsif($view_code eq 'login')
			{
				$sub = $self->load_template('login.tmpl');
			}
			elsif($view_code eq 'signup')
			{
				$sub = $self->load_template('signup.tmpl');
			}
			elsif($view_code eq 'forgot_pass')
			{
				$sub = $self->load_template('forgot_pass.tmpl');
			}
			
			if($sub)
			{
				my $blob = $sub->output;
				my @titles = $blob=~/<title>(.*?)<\/title>/g;
				#$title = $1 if !$title;
				@titles = grep { !/\$/ } @titles;
				$tmpl->param(page_title => shift @titles);
				$tmpl->param(page_content => $blob);
			}
			
			if($page_obj)
			{
				$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
			}
			
			#$r->output($page_obj->content);
			$r->output($tmpl->output);
		}
	};
	
};
1;