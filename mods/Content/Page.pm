# Package: Content::Page
# Base package for content pages
use strict;

package Content::Page;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Page',
		class_title	=> 'Page Database',
		
		table		=> $AppCore::Config::PAGE_DBTABLE || 'pages',
		
		schema	=>
		[
			{
				'field'	=> 'pageid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			# Type is like a "Content-Type" for the page:
			# - Basic "Static" page 
			# - Custom types like a Blog app, News app, etc
			# Types can generate custom content or use the content in this object in some manner
			{	field	=> 'typeid',		type	=> 'int(11)',	linked => 'Content::Page::Type' },
			# The next page up in the nav structure
			{	field	=> 'parentid',		type	=> 'int(11)',	linked => 'Content::Page' },
			{	field	=> 'url',		type	=> 'varchar(255)' },
			{	field	=> 'title',		type	=> 'varchar(255)' },
			{	field	=> 'nav_title',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'teaser',		type	=> 'varchar(255)' },
			{	field	=> 'content',		type	=> 'text' },
			{	field	=> 'extended_data',	type	=> 'text' }, # JSON-encoded attributes for extra Page::Type storage
			{	field	=> 'show_in_menus',	type	=> 'int(1)' },
			{	field	=> 'menu_index',	type	=> 'int(11)', default => 1 },

			
		]	
	
	});
	
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update('Content::Page');	
		$self->mysql_schema_update('Content::Page::Type');
	}
};

package Content::Page::Type;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Page Type',
		class_title	=> 'Page Type Database',
		
		table		=> $AppCore::Config::PAGETYPE_DBTABLE || 'page_types',
		
		schema	=>
		[
			{
				'field'	=> 'typeid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'name',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'controller',	type	=> 'varchar(255)' },
			{	field	=> 'view_code',		type	=> 'varchar(255)' },
		]
	
	});
	
	
	sub process_page
	{
		# Calls controller to do the real work
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		if($self->controller)
		{
			# Assume controller is loaded
			my $pkg = $self->controller;
			
			if($pkg == __PACKAGE__)
			{
				# They really meant to call the base class for types
				$pkg = 'Content::Page::Controller';
			}
			
			undef $@;
				
			eval
			{
				# Pass $self as the first arg so subclasses can access the ID of this type
				$pkg->process_page($self,$req,$r,$page_obj);
			};
			
			if($@)
			{
				$r->error("Error Outputting Page","The controller object '<i>$pkg</i>' had a problem processing your page:<br><pre>$@</pre>"); 
			}
		}
		else
		{
			failover_output($r,$page_obj);
		}
		
		return $r;
	}
	
	sub failover_output
	{
		shift if $_[0] eq __PACKAGE__;
		my $r = shift;
		my $page_obj = shift;
		$r->output($page_obj->content);
	}
};

package Content::Page::Controller;
{
	our %ViewInstCache;
	sub get_view
	{
		my $self      = shift;
		my $view_code = shift;
		my $r         = shift;
		
		my $pkg = $AppCore::Config::THEME_MODULE;
		if(!$pkg )
		{
			$pkg = 'Content::Page::ThemeEngine';
		}
		
		$view_code = 'default' if !$view_code;
		
		if($pkg->can('new'))
		{
			return $ViewInstCache{$pkg}->get_view($view_code,$r) if $ViewInstCache{$pkg};
			
			$ViewInstCache{$pkg} = $pkg->new();
			
			return $ViewInstCache{$pkg}->get_view($view_code,$r);
		}
		else
		{
			return $pkg->get_view($view_code,$r);
		}
	}
	
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# No view code will just return the BasicView derivitve which just uses the basic.tmpl template
		my $view_code = $type_dbobj->view_code;
		
		#print STDERR "process_page: view_code is '$view_code', type: $type_dbobj\n";
		
		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
		my $view = $self->get_view($view_code,$r);
		
		# Pass the view code onto the view output function so that it can aggregate different view types into one module
		$view->output($page_obj,$r,$view_code);
	};

};

package Content::Page::ThemeEngine;
{
	use Scalar::Util 'blessed';
	
	sub new
	{
		bless 
		{
			params => {},
		}, shift;
	}
	
	sub get_view
	{
		my $self = shift;
		my $code = shift;
		my $response = shift;
		$self->{view_code} = $code;
		$self->{response}  = $response;
		$self->{params}    = {};
		return $self;
	}
	
	sub param
	{
		my $self = shift;
		my $key = shift;
		my $value = shift;
		$self->{params}->{$key} = $value;
	}
	
	our @NavCache;
	sub load_nav
	{
		return \@NavCache if @NavCache;
		 
		use Data::Dumper;
		
		my @pages = Content::Page->retrieve_from_sql('show_in_menus=1 order by menu_index, url');
		#die Dumper \@pages;
		my %hash; # = ( root=>{kids=>{}} );
		
		#print STDERR "Building nav...\n";
		foreach my $page (@pages)
		{
			my @url = split /\//, $page->url;
			shift @url;
			
			#print STDERR "Processing page ".$page->url."\n";
		
			my $root = shift @url;
			my $ref = $hash{$root};
			if(!$ref)
			{
				if(@url)
				{
					die $page->url.": No root entry for $root, this is not that page!".Dumper(\%hash);
				}
				else
				{
					$hash{$root} = 
					{
						title	=> $page->title,
						url	=> $page->url,
						kid_map	=> {},
						kids	=> []
					};
					
					$ref = $hash{$root};
					push @NavCache, $ref;
					
					#print STDERR $page->url.": Adding entry for '$root'".Dumper(\%hash);
				}
			}
			
			while(@url)
			{
				my $part = shift @url;
				
				my $new_ref = $ref->{kid_map}->{$part};
				if(!$new_ref)
				{
					if(@url)
					{
						die $page->url.": No entry for url part $part, this is not that page!";
					}
					else
					{
						$new_ref = $ref->{kid_map}->{$part} = 
						{
							title	=> $page->title,
							url	=> $page->url,
							kid_map	=> {},
							kids	=> []
						};
						push @{$ref->{kids}}, $new_ref;
					}
				}
			}
		}
		
		#die Dumper \@NavCache;
		return \@NavCache;
		
	}
	
	sub apply_page_obj
	{
		my ($self,$tmpl,$page_obj) = @_;
		if(blessed $page_obj && $page_obj->isa('Content::Page'))
		{
			my $user = AppCore::Common->context->user;
			$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
			$tmpl->param(page_content => AppCore::Web::Common::load_template($page_obj->content)->output) if $page_obj->content =~ /%%/;
			$tmpl->param(page_title   => AppCore::Web::Common::load_template($page_obj->title  )->output) if $page_obj->title   =~ /%%/;
			$tmpl->param(content_url  => AppCore::Common->context->current_request->page_path);
			$tmpl->param(can_edit     => $user && $user->check_acl(['ADMIN']));
			 
			return 1;
		}
		
		return 0;
	}

	sub output
	{
		my $self       = shift;
		my $page_obj   = shift || undef;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $parameters = shift || {};
		
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
	
	sub load_template
	{
		my $self = shift;
		my $file = shift;
		my $pkg  = ref $self;
		my $tmpl = undef;
		if($pkg ne 'Content::Page::ThemeEngine')
		{
			my $tmp_file_name = 'mods/'.$pkg.'/tmpl/'.$file;
			if($file !~ /^\// && -f $tmp_file_name)
			{
				$tmpl = AppCore::Web::Common::load_template($tmp_file_name);
			}
			else
			{
				print STDERR "Template file didnt exist: $tmp_file_name\n";
			}
		}
		
		if(!$tmpl)
		{
			$tmpl = AppCore::Web::Common::load_template($file);
		}
		
		if($tmpl)
		{
			$tmpl->param(appcore => join('/', $AppCore::Config::WWW_ROOT));
			$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', $pkg));
			$tmpl->param($_ => $self->{params}->{$_}) foreach keys %{$self->{params}};
			$tmpl->param(mainnav      => $self->load_nav); 
			
			my $user = AppCore::Common->context->user;
			$tmpl->param(is_admin => $user && $user->check_acl(['ADMIN']));
		}
	
		return $tmpl;
	}
};

1;
