use strict;

package Boards::TextFilter::TagVerses;
{ 
	use base 'Boards::TextFilter';
	__PACKAGE__->register("Bible Verse Links","Hyperlink Bible verses in text");
	
	sub filter_text
	{
		shift if $_[0] eq __PACKAGE__;
		my $textref = shift;
		ThemePHC::VerseLookup->tag_verses($textref);
	};
	
	sub replace_block
	{
		shift if $_[0] eq __PACKAGE__;
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
	use ThemePHC::Videos;
	use ThemePHC::Groups;
	use ThemePHC::Search;
	use ThemePHC::LivePage;
	use ThemePHC::AskPastor;
	use ThemePHC::Audio;
	
	# Load the board controllers so it can update user prefs
	use ThemePHC::BoardsTalk;
	use ThemePHC::PastorsBlog;
	
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
		my @sub_mods = qw{
			ThemePHC::Missions
			ThemePHC::Directory
			ThemePHC::Events
			ThemePHC::Videos
			ThemePHC::Groups
			ThemePHC::Search
			ThemePHC::Audio
		};
		$_->apply_mysql_schema foreach @sub_mods;
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
			#timemark
			
			$tmpl = $self->load_template('frontpage.tmpl');
			
			#timemark('load tmpl');
			
			# Load list of posts using the Boards controller
			# bootstrap() should cache the module object reference, so we don't use up more memory than needed
			my $controller = AppCore::Web::Module->bootstrap('Boards');
			
			#timemark('boostrap boards');
			
			# If we dont specify, it assumes '/themephc'
			$controller->binpath('/boards'); 
			
			# Apply video provider data in case any of the posts are videos.
			# frontpage.tmpl will include the relevant video scripts template
			$controller->apply_video_providers($tmpl);
			
			#timemark('apply vid providers');
			
			# Board '1' is the prayer/praise/talk board
			my $data = $controller->load_post_list(Boards::Board->retrieve(1));
			
			#timemark('load post list');
			
			$tmpl->param('talk_'.$_ => $data->{$_}) foreach keys %$data;
			
			# Used by the list of slides on the right - note forced stringification required below.
			$tmpl->param('talk_approx_time' => ''.approx_time_ago($data->{first_ts}));
			
# 			use Data::Dumper;
# 			die Dumper $data;

			#timemark('boards done');

			# Load list of upcoming events
			$controller = AppCore::Web::Module->bootstrap('ThemePHC::Events');
			$controller->binpath('/connect/events');
			
			#timemark('boostrap events');
			
			my $event_data = $controller->load_basic_events_data();
			
			#timemark('load events list');
			
			$tmpl->param(events_dated  => $event_data->{dated});
			$tmpl->param(events_weekly => $event_data->{weekly});
			
			# Give it just the next three events
			$tmpl->param(events_dated_three  => [ @{ $event_data->{dated} }[0..2] ]);
			
			#timemark('events done');
			
			# Load most recent video
			my $data = $controller->load_post_list(Boards::Board->by_field(folder_name => 'videos'), {idx=>0, len=>1});  # Load only one video
			
			# Extract the Vimeo Video ID from the URL in the text
			my $post = $data->{posts}->[0];
			my ($code) = $post->{text} =~ /vimeo\.com\/(\d+)/;
			
			# Clean up the subject
			my $subj = $post->{subject};
			$subj =~ s/"([^\"]+)"/<span class='ldquo'>&#8220;<\/span>$1<span class='rdquo'>&#8221;<\/span>/g;
			$subj =~ s/^PHC Sunday (Morning|Evening) Sermon - //g;
			
			# Add the code and subject to template
			$tmpl->param(recent_videoid => $code);
			$tmpl->param(recent_vidtitle => $subj);
			
			# Remove the date from the subject and also add to template (used to title the block in an <h1> tag above the iframe)
			$subj =~ s/- [\d-]+$//g;
			$tmpl->param(recent_vidtitle_nodate => $subj);
			
						
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
 		
 		#print STDERR __PACKAGE__."::remap_template(): $pkg wants '$file', isa? ".(UNIVERSAL::isa($pkg,'Boards') ? "yes":"no")."\n";
 		my $abs_file = undef;
 		if(UNIVERSAL::isa($pkg,'Boards'))
 		{
 			if($file eq 'list.tmpl' ||
 			   $file eq 'post.tmpl')
 			{
 				# Repmap the list.tmpl from Boards into our template folder 
 				$abs_file = $class->get_template_path('boards/'.$file);
 			}
 		}
 		elsif($pkg eq 'User')
 		{
 			if($file eq 'signup.tmpl' ||
 			   $file eq 'forgot_pass.tmpl')
 			{
 				# Repmap the list.tmpl from Boards into our template folder 
 				$abs_file = $class->get_template_path('user/'.$file);
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
