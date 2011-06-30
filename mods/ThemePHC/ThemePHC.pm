use strict;

package Boards::TextFilter::TagVerses;
{ 
	use base 'Boards::TextFilter';
	__PACKAGE__->register("Bible Verse Links","Hyperlink Bible verses in text");
	
	sub filter_text
	{
		my $self = shift;
		my $textref = shift;
		ThemePHC::VerseLookup->tag_verses($textref);
	};
	
	sub replace_block
	{
		my $block = shift;
		__PACKAGE__->filter_text(\$block);
		return $block;
	}
	
};

package ThemePHC;
{
	use AppCore::Common;
	use Content::Page;
	use base 'Content::Page::ThemeEngine';
	use Scalar::Util 'blessed';
	
	# Load verselookup so its in ram and so it gets its schema updated as needed
	use ThemePHC::VerseLookup;
	
	# Load our modules so they gets registered with the page type database
	use ThemePHC::Missions;
	use ThemePHC::Directory;
	use ThemePHC::Events;
	
	# Load the talk controller so it can update user prefs
	use ThemePHC::BoardsTalk;
	
	__PACKAGE__->register_theme('PHC 2011','Pleasant Hill Church 2011 Website Update', [qw/home admin sub mobile/]);
	
	# Hook for our database objects
	sub apply_mysql_schema
	{
		#ThemePHC::VerseLookup->apply_mysql_schema;
		my $self = shift;
		my @db_objects = qw{
			ThemePHC::VerseLookup
		};
		AppCore::DBI->mysql_schema_update($_) foreach @db_objects;
		
		# Make sure missions and other sub modules are in sync
		ThemePHC::Missions->apply_mysql_schema();
		ThemePHC::Directory->apply_mysql_schema();
		ThemePHC::Events->apply_mysql_schema();
	}
	
	sub load_nav_hook 
	{
		my $self = shift;
		my $nav_ref = shift;
		if($nav_ref->{url} eq '/serve/outreach')
		{
			# hehehe...code reuse at it's best...
			my $list = ThemePHC::Missions->load_missions_list;
			
			my @kids;
			foreach my $country (@{$list || []})
			{
				foreach my $m (@{$country->{list} || []})
				{
					push @kids, {
						title	=> $m->{list_title},
						url	=> join('/', $nav_ref->{url}, $m->{board_folder_name}),
						kid_map	=> {},
						kids	=> [],
					}
				}
			}
			
			@kids = sort {$a->{title} cmp $b->{title}} @kids;
			
			$nav_ref->{kids} = \@kids;
		}
	}
	
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
			
			# Load list of posts using the Boards controller
			# bootstrap() should cache the module object reference, so we don't use up more memory than needed
			my $controller = AppCore::Web::Module->bootstrap('Boards');
			
			# If we dont specify, it assumes '/themephc'
			$controller->binpath('/boards'); 
			
			# Apply video provider data in case any of the posts are videos.
			# frontpage.tmpl will include the relevant video scripts template
			$controller->apply_video_providers($tmpl);
			
			# Board '1' is the prayer/praise/talk board
			my $data = $controller->load_post_list(Boards::Board->retrieve(1));
			$tmpl->param('talk_'.$_ => $data->{$_}) foreach keys %$data;
			
			# Used by the list of slides on the right - note forced stringification required below.
			$tmpl->param('talk_approx_time' => ''.approx_time_ago($data->{first_ts}));
			
# 			use Data::Dumper;
# 			die Dumper $data;

			# Load list of upcoming events
			$controller = AppCore::Web::Module->bootstrap('ThemePHC::Events');
			$controller->binpath('/connect/events');
			
			my $event_data = $controller->load_basic_events_data();
			$tmpl->param(events_dated  => $event_data->{dated});
			$tmpl->param(events_weekly => $event_data->{weekly});
			
			# Give it just the next three events
			$tmpl->param(events_dated_three  => [ @{ $event_data->{dated} }[0..2] ]);
			
			
			# TODO: Load recent videos 
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
 		my $pkg   = shift;
 		my $file  = shift;
 		
 		#print STDERR __PACKAGE__."::remap_template(): $pkg wants '$file'\n";
 		my $abs_file = undef;
 		if($pkg eq 'Boards')
 		{
 			if($file eq 'list.tmpl' ||
 			   $file eq 'post.tmpl')
 			{
 				# Repmap the list.tmpl from Boards into our template folder 
 				$abs_file = $class->get_template_path('boards/'.$file);
 			}
 		}
 		
 		#print STDERR __PACKAGE__."::remap_template(): $pkg wants '$file', giving '$abs_file'\n" if defined $abs_file;
 		
		return $abs_file; 
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
