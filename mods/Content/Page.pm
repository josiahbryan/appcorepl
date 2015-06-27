# Package: Content::Page
# Base package for content pages
use strict;

package Content::Page;
{
	use base 'AppCore::DBI';
	use JSON qw/decode_json encode_json/;
	
	__PACKAGE__->meta({
		class_noun	=> 'Page',
		class_title	=> 'Page Database',
		
		table		=> AppCore::Config->get("PAGE_DBTABLE") || 'pages',
		
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
			{	field	=> 'themeid',		type	=> 'int(11)',	linked => 'Content::Page::ThemeEngine' },
			{	field	=> 'view_code',		type	=> 'varchar(100)', default => 'sub' },
			# The next page up in the nav structure
			{	field	=> 'parentid',		type	=> 'int(11)',	linked => 'Content::Page' },
			{	field	=> 'url',		type	=> 'varchar(255)' },
			{	field	=> 'redirect_url',	type	=> 'varchar(255)' },
			{	field	=> 'title',		type	=> 'varchar(255)' },
			{	field	=> 'nav_title',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'teaser',		type	=> 'varchar(255)' },
			{	field	=> 'acl',		type	=> 'text' },
			{	field	=> 'content',		type	=> 'text' },
			{	field	=> 'mobile_content',	type	=> 'text' },
			{	field	=> 'mobile_alt_url',	type	=> 'varchar(255)' },
			{	field	=> 'extended_data',	type	=> 'text' }, # JSON-encoded attributes for extra Page::Type storage
			{	field	=> 'show_in_menus',	type	=> 'int(1)' },
			{	field	=> 'menu_index',	type	=> 'varchar(100)', default => 0 },
			{	field	=> 'timestamp',		type	=> 'timestamp' },
			
		]	
	
	});
	
	
	sub set_extended_data
	{
		my $self = shift;
		my $ref = shift;
		my $no_update = shift || 0;
		my $data = encode_json($ref);
		if($self->extended_data ne $data)
		{
			$self->extended_data($data);
			$self->update unless $no_update;
		}
	}
	
	sub get_extended_data
	{
		my $self = shift;
		return decode_json($self->extended_data || '{}'); 
	}
	
	
	sub apply_mysql_schema
	{
		my $self = shift;
		my @db_objects = qw{
			Content::Page
			Content::Page::Type
			Content::Page::ThemeEngine
			Content::Page::ThemeEngine::View
		};
		$self->mysql_schema_update($_) foreach @db_objects;
	}
	
	sub check_acl
	{
		my $self = shift;
		my $user = AppCore::Common->context->user;
		my $acl = $self->{_acl};
		if(!$acl)
		{
			my @list = split /,/, $self->acl;
			s/(^\s+|\s+$)//g foreach @list;
			$acl = $self->{_acl} = \@list;
		}
			 
		$acl = [] if ref $acl ne 'ARRAY';
		return 1 if !@$acl || (@$acl && $acl->[0] eq 'EVERYONE' && !$user);
		return $user->check_acl($acl) if $user;
		return 0 if @$acl;
		return 1;
	}
};

package Content::Page::Type;
{
	use base 'AppCore::DBI';
	use JSON qw/encode_json decode_json/;
	
	__PACKAGE__->meta({
		class_noun	=> 'Page Type',
		class_title	=> 'Page Type Database',
		
		table		=> AppCore::Config->get("PAGETYPE_DBTABLE") || 'page_types',
		
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
			{	field	=> 'uses_pagepath',	type	=> 'int(1)', default => 0 },
			{	field	=> 'uses_content',	type	=> 'int(1)', default => 1 },
			{	field	=> 'custom_fields',	type	=> 'text' },
		]
	
	});
	
	sub set_custom_fields
	{
		my $self = shift;
		my $listref = shift;
		my $no_update = shift || 0;
		my $data = encode_json($listref);
		if($self->custom_fields ne $data)
		{
			$self->custom_fields($data);
			$self->update unless $no_update;
		}
	}
	
	sub get_custom_fields
	{
		my $self = shift;
		return decode_json($self->custom_fields); 
	}
	
	sub type_for_controller
	{
		my $self = shift;
		return $self->by_field(controller => shift);
	}
	
	sub default_type
	{
		return shift->type_for_controller('Content::Page::Controller');
	}
	
	sub register
	{
		my $class = shift;
		
		my $pkg = shift;
		$pkg = ref $pkg if ref $pkg;
		
		my $name = shift;
		my $diz = shift;
		
		my $uses_pagepath = shift || 0;
		my $uses_content  = shift;
		$uses_content = 1 if !defined $uses_content;
		
		my $field_list = shift || [];
		
		my $self = undef;
		undef $@;
		eval
		{
			$self = $class->find_or_create({controller=>$pkg});
			
			$self->name($name)                   if $self->name          ne $name;
			$self->description($diz)             if $self->description   ne $diz;
			$self->uses_pagepath($uses_pagepath) if $self->uses_pagepath != $uses_pagepath;
			$self->uses_content($uses_content)   if $self->uses_content  != $uses_content;
			$self->set_custom_fields($field_list, 1); # 1 = dont update even if changed
			$self->update if $self->is_changed;
		};
		warn $@ if $@;
		
		return $self;
		
	}
	
	sub tmpl_select_list
	{
		my $pkg = shift;
		my $cur = shift;
		my $curid = ref $cur ? $cur->id : $cur;
		
		my @all = $pkg->retrieve_from_sql('1 order by name');
		my @list;
		foreach my $item (@all)
		{
			push @list, {
				value	=> $item->id,
				text	=> $item->name,
				hint	=> $item->description,
				selected => $item->id == $curid,
				uses_content => $item->uses_content,
			}
		}
		return \@list;
	}
	
	our %ControllerObjectCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing controllers...\n";
		%ControllerObjectCache = ();
	}	
	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	
	sub process_page
	{
		# Calls controller to do the real work
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# Assume controller is loaded
		my $pkg = $self->controller;
		$pkg = 'Content::Page::Controller' if !$pkg;
		
		if($pkg eq __PACKAGE__)
		{
			# They really meant to call the base class for types
			$pkg = 'Content::Page::Controller';
		}
		
		if($pkg->can('new'))
		{
			my $pkg_name = ref $pkg ? ref $pkg : $pkg;
			if(!$ControllerObjectCache{$pkg_name})
			{
				$pkg = $pkg->new();
				#print STDERR __PACKAGE__."->process_page(): Created new controller '$pkg'\n";
			}
			else
			{
				$pkg = $ControllerObjectCache{$pkg_name};
				#print STDERR __PACKAGE__."->process_page(): Used cached controller '$pkg'\n";
			}
		}
			
		undef $@;
		
		eval
		{
			# Pass $self as the first arg so subclasses can access the ID of this type
			$pkg->process_page($self,$req,$r,$page_obj);
		};
		
		if(my $error = $@)
		{
			if($error =~ /MySQL server has gone away/)
			{
				# Propogate database error
				die $error;
			}
			elsif(UNIVERSAL::isa($error, 'AppCore::Web::Common::RequestException'))
			{
				$r->{status}  = $error->{code}; 
				push @{$r->{headers}}, @{$error->{headers} || []};
				$r->{body}    = $error->{body};
				
				# Grab Content-Type from the headers array if present
				# because 'content_type' is a "special" header used in AppCore - poor design, I know.
				my @ctype =
					grep { lc $_->[0] eq 'content-type' }
					@{$error->{headers} || []};
					
				$r->{content_type} = $ctype[0]->[1]
					if @ctype;
			}
			else
			{
# 				#die $error;
# 				$r->{status}  = 500;
# 				#$r->{headers} = [["Content-Type","text/html"]];
# 				#$r->{body}    = "The controller object '<i>$pkg</i>' had a problem processing your page:<br><pre>$error</pre>";
# 				$r->{body}    = $error; #"The controller object '<i>$pkg</i>' had a problem processing your page:<br><pre>$error</pre>";
# 				$r->{content_type} = "text/plain";
# 				
				$r->error("Error Outputting Page","The controller object '<i>$pkg</i>' had a problem processing your page:<br><pre style='white-space:pre-wrap'>$error</pre>");
			}
			
			
			
		}
		
		return $r;
	}
};

package Content::Page::Controller;
{
	Content::Page::Type->register(__PACKAGE__, 'Static Page','Simple static webpage');
	
	sub register_controller
	{
		my $pkg = shift;
		return Content::Page::Type->register($pkg, @_);
	}
	
	our %ViewInstCache;
	
	our $CurrentView;
	sub current_view
	{
		return $CurrentView;
	}
	
	our $CurrentTheme;
	sub theme
	{
		my $self = shift;
# 		if(@_)
# 		{
# 			return $CurrentTheme = shift;
# 		}
# 		if(!$CurrentTheme)
		{
			$CurrentTheme = AppCore::Config->get("THEME_MODULE");
		}
		if(!$CurrentTheme)
		{
			$CurrentTheme = 'Content::Page::ThemeEngine';
		}
		
		return $CurrentTheme;
	}
	
	use AppCore::Common;
	sub get_view
	{
		my $self      = shift;
		my $view_code = shift;
		my $r         = shift;
		
		my $pkg = $self->theme;
		
		$view_code = 'default' if !$view_code;
		
		my $view_getter = undef;
		
		if($pkg->can('new'))
		{
# 			return $CurrentView = $ViewInstCache{$pkg}->get_view($view_code,$r) if $ViewInstCache{$pkg};
# 			
# 			$ViewInstCache{$pkg} = $pkg->new();
# 			
# 			return $CurrentView = $ViewInstCache{$pkg}->get_view($view_code,$r);

			#return $CurrentView = $ViewInstCache{$pkg}->get_view($view_code,$r) if $ViewInstCache{$pkg};
			
			if(!$ViewInstCache{$pkg})
			{
				$view_getter = $ViewInstCache{$pkg} = $pkg->new();
			}
			else
			{
				$view_getter = $ViewInstCache{$pkg};
			}
			
			#return $CurrentView = $ViewInstCache{$pkg}->get_view($view_code,$r);
		}
		else
		{
			#return $CurrentView = $pkg->get_view($view_code,$r);
			$view_getter = $pkg;
		}
		
		#timemark("start get_view/C::P::Ctrl");
		$CurrentView = $view_getter->get_view($view_code,$r);
		#timemark("end get_view/C::P::Ctrl");
		
		return $CurrentView;
	}
	
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		if(UNIVERSAL::isa($self,'AppCore::Web::Module'))
		{
			# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
			# (but %%modpath%% will return the appros module for resources such as images)
			my $new_binpath = AppCore::Config->get('DISPATCHER_URL_PREFIX') . $req->page_path; # this should work...
			#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath' ($self)\n";
			$self->binpath($new_binpath);
			
			## Redispatch thru the ::Module dispatcher which will handle calling main_page()
			return $self->dispatch($req, $r);
		}
		
		# No view code will just return the BasicView derivitve which just uses the basic.tmpl template
		my $themeid   = $page_obj ? $page_obj->themeid   : undef;
		my $view_code = $page_obj ? $page_obj->view_code : undef;
		
		if($themeid && $themeid->id)
		{
			# Change current theme if the page requests it
			$self->theme($themeid->controller);
		}
		
		#print STDERR "process_page: view_code is '$view_code', type: $type_dbobj\n";
		
		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
		my $view = $self->get_view($view_code,$r);
		
		# Pass the view code onto the view output function so that it can aggregate different view types into one module
		$view->output($page_obj,$r,$view_code);
	};

};

package Content::Page::ThemeEngine::BreadcrumbList;
{
	sub new
	{
		my $class = shift;
		my $view = shift;
		return bless { list=> [], view=> $view }, $class;
	};
	
	sub view { shift->{view} }
	
	sub last_crumb
	{
		my @list = @{shift->{list}};
		return $list[$#list] if @list;
		return {} if !@list;
	}
	
	sub list
	{
		my $self = shift;
		
		my @tmp = @{$self->{list}};
		my @final;
		my $last = undef;
		foreach my $item (@tmp)
		{
			next if $last && $item->{url} eq $last->{url};
			$last = $item;
			$item->{current} = 0;
			if($item->{title} =~ /%%/)
			{
				$item->{title} = AppCore::Web::Common::load_template($item->{title})->output;
			}
			push @final, $item;
		}
		
		$final[$#final]->{current} = 1 if @final;

		#use Data::Dumper;
		#die Dumper \@final;
		
		return \@final; 
	}
	
	sub clear
	{
		my $self = shift;
		$self->{list} = [];
	}
	
	sub push
	{
		my $self = shift;
		my $ref = shift;
		
		# Assume more than one arg is (title,url,current) trifecta
		if(@_)
		{
			$ref = 
			{
				title => $ref,
				url   => shift,
				current => shift,
			};
		}
		
		
		warn __PACKAGE__."::push(): No 'title' in arguments" if !$ref->{title};
		if(!$ref->{url})
		{
			AppCore::Common->print_stack_trace();
			warn __PACKAGE__."::push(): No 'url' in arguments";
		}
		$ref->{current} = 0 if !defined $ref->{current};
		
		push @{$self->{list}}, $ref;
		
		return $self;
	}
	
	sub pop
	{
		my $self = shift;
		pop @{$self->{list}};
	}
};

package Content::Page::ThemeEngine::View;
{
	use Scalar::Util 'blessed';
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'View Code',
		
		table		=> AppCore::Config->get("THEMES_DBTABLE") || 'theme_views',
		
		schema	=>
		[
			{
				'field'	=> 'viewid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'themeid',		type	=> 'int(11)',	linked => 'Content::Page::ThemeEngine' },
			{	field	=> 'name',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'view_code',		type	=> 'varchar(255)' },
		]
	
	});
	
	sub tmpl_select_list
	{
		my $pkg = shift;
		my $cur = shift;
		my $theme = shift;
		my $themeid = ref $theme ? $theme->id : $theme;
		
		my @all = $pkg->retrieve_from_sql(($themeid ? 'themeid='.$themeid : '1').' order by name');
		my @list;
		foreach my $item (@all)
		{
			push @list, {
				value	=> $item->view_code,
				text	=> $item->name,
				hint	=> $item->description,
				selected => $item->view_code eq $cur,
			}
		}
		return \@list;
	}
};

# package Content::Page::ThemeEngine::UserActionHook;
# {
# 	#use User;
# 	use base 'User::ActionHook';
# 	
# 	__PACKAGE__->register(User::ActionHook::EVT_ANY);
# 	
# 	sub hook
# 	{
# 		my ($self,$event,$args) = @_;
# 		
# 		if($event eq User::ActionHook::EVT_USER_LOGIN ||
# 		   $event eq User::ActionHook::EVT_USER_LOGOUT ||
# 		   $event eq User::ActionHook::EVT_USER_ADDED_TO_GROUP)
# 		{
# 			print STDERR __PACKAGE__.": User event: '$event', clearing nav cache\n";
# 			Content::Page::ThemeEngine->clear_nav_cache();
# 		}
# 	}
# };



package Content::Page::ThemeEngine;
{
	use Scalar::Util 'blessed';
	use base 'AppCore::DBI';
	
	# For subnav modifications...
	#use Clone::More qw( clone );

	sub clone
	{
		my $ref = shift;
		return $ref if !ref($ref) || !$ref;
		if(ref $ref eq 'ARRAY' ||
		   ref $ref eq 'DBM::Deep::Array')
		{
			my @new_array;
			my @old_array = @$ref;
			foreach my $line (@old_array)
			{
				push @new_array, clone($line);
			}
			return \@new_array;
		}
		#elsif(ref $ref eq 'HASH' ||
		#      ref $ref eq 'DBM::Deep::Hash')
		else
		{
			my %new_hash;
			my %old_hash = %$ref;
			my @keys = keys %old_hash;
			foreach my $key (keys %old_hash)
			{
				$new_hash{$key} = clone($old_hash{$key});
			}
			return \%new_hash;
		}
		warn "clone($ref): Could not clean ref type '".ref($ref)."'";
		return $ref;
	}


	
	__PACKAGE__->meta({
		class_noun	=> 'Theme Engine',
		
		table		=> AppCore::Config->get("THEMES_DBTABLE") || 'themes',
		
		schema	=>
		[
			{
				'field'	=> 'themeid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'name',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'controller',	type	=> 'varchar(255)' },
		],
		has_many	=> qw/Content::Page::ThemeEngine::View/,
	});
	
	sub tmpl_select_list
	{
		my $pkg = shift;
		my $cur = shift;
		my $curid = ref $cur ? $cur->id : $cur;
		
		my @all = $pkg->retrieve_from_sql('1 order by name');
		my @list;
		foreach my $item (@all)
		{
			push @list, {
				value	=> $item->id,
				text	=> $item->name,
				hint	=> $item->description,
				selected => $item->id == $curid,
			}
		}
		return \@list;
	}
	
	
	sub register_viewcodes
	{
		my $self = shift;
		my @list = @_;
		@list = @{$list[0]} if ref $list[0] eq 'ARRAY';
		foreach my $viewcode (@list)
		{
			if(ref $viewcode eq 'HASH')
			{
				$viewcode->{themeid} = $self;
				Content::Page::ThemeEngine::View->find_or_create($viewcode);
			}
			else
			{
				Content::Page::ThemeEngine::View->find_or_create({
					themeid	=> $self,
					name	=> AppCore::Common->guess_title($viewcode),
					view_code => $viewcode,
				});
			}
		}
	}
	
	sub register_theme
	{
		my $theme_ref = undef;
		undef $@;
		eval
		{
			my $pkg = shift;
			$pkg = ref $pkg if ref $pkg;
			
			my $name = shift;
			my $diz = shift;
			my @codes = @_;
			
			my $self = $pkg->find_or_create({controller=>$pkg});
			
			$self->name($name) if $self->name ne $name;
			$self->description($diz) if $self->description ne $diz;
			$self->update if $self->is_changed;
			
			$self->register_viewcodes(@codes) if @codes;
			
			$theme_ref = $self;
			
		};
		warn $@ if $@;
		
		return $theme_ref;
		
	}
	
	sub theme_for_controller
	{
		my $pkg = shift;
		my $controller = shift || Content::Page::Controller->theme();
		return $pkg->by_field(controller => $controller);
	} 
	
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
		$self->{bc_list}   = Content::Page::ThemeEngine::BreadcrumbList->new($self); 
		$Content::Page::Controller::CurrentView = $self;
		return $self;
	}
	
	sub breadcrumb_list
	{
		return shift->{bc_list};
	}
	
	sub param
	{
		my $self = shift;
		my $key = shift;
		my $value = shift;
		$self->{params}->{$key} = $value;
	}
	
	our @NavCache;
	our %NavMap;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing navigation cache...\n";
		clear_nav_cache();
	}	
	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	sub clear_nav_cache
	{
		@NavCache = ();
		%NavMap = ();
	}
	
	sub load_nav
	{
		return \@NavCache if @NavCache;
		my $self = shift;
		 
		use Data::Dumper;
		
		my @pages = Content::Page->retrieve_from_sql('show_in_menus=1 order by menu_index, url');
		#die Dumper \@pages;
		my %hash; # = ( root=>{kids=>{}} );

		my $current_url = AppCore::Common->context->current_request->page_path;
		
		#print STDERR "Building nav...\n";
		foreach my $page (@pages)
		{
			next if !$page->check_acl;
			
			my @url = split /\//, $page->url;
			shift @url;
			
			#print STDERR "Processing page ".$page->url."\n";
		
			my $root = shift @url;
			my $ref = $hash{$root};
			if(!$ref)
			{
				if(@url)
				{
					#die $page->url.": No root entry for $root, this is not that page!".Dumper(\%hash);
					# Root isnt in menu, so ignore children
				}
				else
				{
					my $page_url = $page->url;
					my $no_slash = $page_url;
					$no_slash =~ s/^\///g;
					$hash{$root} = 
					{
						title	=> $page->title,
						url	=> $page_url,
						no_slash=> $no_slash,
						kid_map	=> {},
						kids	=> [],
						current => $page_url eq $current_url || $page_url eq '/' && !$current_url || $current_url eq '/' && !$page_url,
					};
					$ref = $hash{$root};
					$self->load_nav_hook($ref);
					push @NavCache, $ref;
					
					#print STDERR $page->url.": Adding entry for '$root'".Dumper(\%hash);
				}

				$NavCache[0]->{first} = 1 if @NavCache;
				$NavCache[$#NavCache]->{last} = 1 if @NavCache;
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
						$self->load_nav_hook($new_ref);
						push @{$ref->{kids}}, $new_ref;
					}
				}
				
				$ref = $new_ref;
			}
		}
		
		#die Dumper \@NavCache;
		%NavMap = %hash;
		return \@NavCache;
		
	}
	
	# Hook for subclasses
	sub load_nav_hook {}
	
	
	our %PageDataCache;
	our %SubnavCache;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing data...\n";
		%SubnavCache = ();
		%PageDataCache = ();
	}	
	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__);
	
	sub _create_scribd_embed_html
	{
		my ($id,$key,$mode) = @_;
		
		my $HTML_FORMAT = 'flash';
		return $HTML_FORMAT eq 'flash' ?
		qq{
				<object height="600" width="100%" type="application/x-shockwave-flash" data="http://d1.scribdassets.com/ScribdViewer.swf" style="outline:none" >
				<param name="movie" value="http://d1.scribdassets.com/ScribdViewer.swf">
				<param name="wmode" value="opaque">
				<param name="bgcolor" value="#ffffff">
				<param name="allowFullScreen" value="true">
				<param name="allowScriptAccess" value="always">
				<param name="FlashVars" value="document_id=${id}&access_key=${key}&page=1&viewMode=${mode}">
				<embed src="http://d1.scribdassets.com/ScribdViewer.swf?document_id=${id}&access_key=${key}&page=1&viewMode=${mode}" type="application/x-shockwave-flash" allowscriptaccess="always" allowfullscreen="true" height="600" width="100%" wmode="opaque" bgcolor="#ffffff"></embed>
				</object>
		} :
		qq|
			<iframe class="scribd_iframe_embed" src="http://www.scribd.com/embeds/${id}/content?start_page=1&view_mode=list&access_key=${key}" data-auto-height="true" data-aspect-ratio="0.779617834394905" scrolling="no" width="100%" height="600" frameborder="0"></iframe>
			<script type="text/javascript">(function() { var scribd = document.createElement("script"); scribd.type = "text/javascript"; scribd.async = true; scribd.src = "http://www.scribd.com/javascripts/embed_code/inject.js"; var s = document.getElementsByTagName("script")[0]; s.parentNode.insertBefore(scribd, s); })();</script>
		|;
	}
	
	
	sub apply_page_obj
	{
		my ($self,$tmpl,$page_obj) = @_;
		if(blessed $page_obj && $page_obj->isa('Content::Page'))
		{
			my $ctx = AppCore::Common->context;
			my $pageid = $page_obj->id;
			my $mobile = $ctx->mobile_flag;
			my $key = join(':',$pageid,$mobile);
			my $pgdat = $PageDataCache{$key};
			if(!$pgdat)
			{
				my $user = $ctx->user;
				
				# Substitute alternative content in case of mobile content
				my $content = $mobile && $page_obj->mobile_content ?
					$page_obj->mobile_content :
					$page_obj->content;
				
				$content = AppCore::Web::Common::load_template($content)->output if $content =~ /%%/;
				if($content =~ /\[scribd id=/)
				{
					$content =~ s/\[scribd id=([^\s]+) key=([^\s]+) mode=([^\]]+)\]/_create_scribd_embed_html($1,$2,$3)/egi;
				}
				
				$pgdat->{'page_'.$_}	= $page_obj->get($_) foreach $page_obj->columns;
				$pgdat->{page_content}	= $content;
				$pgdat->{page_title}	= AppCore::Web::Common::load_template($page_obj->title)->output if $page_obj->title   =~ /%%/;
				$pgdat->{content_url}	= $ctx->current_request->page_path;
				$pgdat->{can_edit}	= $user && $user->check_acl(['ADMIN']);
				
				my $subnav = $self->load_subnav($page_obj);
				$pgdat->{$_} = $subnav->{$_} foreach keys %$subnav;
				
				eval
				{
					my $page_tmpl = $self->load_template('page.tmpl');
					if($page_tmpl)
					{
						$page_tmpl->param($_ => $pgdat->{$_}) foreach keys %$pgdat;
						$pgdat->{page_content} = $page_tmpl->output;
					}	
				};
				
				$PageDataCache{$key} = $pgdat;
			}
			
			$tmpl->param($_ => $pgdat->{$_}) foreach keys %$pgdat;
			
			#die Dumper $pgdat if $0 =~ /mrmp/;
			
			return 1;
		}
		
		return 0;
	}
	
	sub load_subnav
	{
		my $self = shift;
		my $page_obj = shift;
		my $url = $page_obj->url;
		
		my $subnav = $SubnavCache{$url};
		if(!$subnav)
		{
			$subnav = {};
			
			my @parts = split /\//, $url;
			#shift @parts; # remove start
			my $len = scalar @parts;
			#print STDERR "load_subnav(): len:$len, parts:".join('|',@parts)."\n";
			if(@parts < 2)
			{
				# no subnav
				#print STDERR "load_subnav(): no subnav\n";
			}
			else
			{
				$self->load_nav();
				
				my @url_base = @parts;
				pop @url_base;
				my $url_base = join('/', @url_base);
				
				my $sth = Content::Page->db_Main->prepare('select pageid from pages where url like ? and show_in_menus=1 order by menu_index');
					
				my @sibs;
				$sth->execute($url_base . '/%');
				push @sibs, Content::Page->retrieve($_) while $_ = $sth->fetchrow;
				
				my @kids;
				$sth->execute($url .'/%');
				push @kids, Content::Page->retrieve($_) while $_ = $sth->fetchrow;
				
				my @tmpl_sibs;
				foreach my $sib (@sibs)
				{
					next if !$sib->check_acl;
					# This test is to eliminate kids from the sibling list
					my $test = $sib->url;
					$test =~ s/^$url_base\///g;
					#print STDERR "$test\n";
					next if $test =~ /\//;
					
					push @tmpl_sibs,
					{
						title => $sib->title,
						url   => $sib->url,
						current => $sib->url eq $page_obj->url,
					};
				}
				$tmpl_sibs[$#tmpl_sibs]->{last} = 1 if @tmpl_sibs;
				
				my @tmpl_kids;
				foreach my $kid (@kids)
				{
					next if !$kid->check_acl;
					
					# This test is to eliminate kids or kids from the kids list
					my $test = $kid->url;
					$test =~ s/^$url\///g;
					#print STDERR "$test\n";
					next if $test =~ /\//;
					
					push @tmpl_kids,
					{
						title => $kid->title,
						url   => $kid->url,
					};
				}
				$tmpl_kids[$#tmpl_kids]->{last} = 1 if @tmpl_kids;
				
				#die Dumper $url_base, \@tmpl_sibs, \@tmpl_kids;
				
				$subnav->{nav_sibs} = @tmpl_kids ? \@tmpl_kids : \@tmpl_sibs;
				$subnav->{nav_kids} = \@tmpl_kids;
				
				my @url_build;
				my @nav_path;
				foreach my $part (@parts)
				{
					push @url_build, $part;
					my $url = join '/', @url_build;
					#$url = '/' if !$url;
					if(!$url)
					{
						push @nav_path,
						{
							title => 'Home',
							url   => '/',
							current => 0,
						};
					}
					else
					{
						my $page = Content::Page->by_field(url => $url);
						if($page)
						{
							my $title = $page->title;
							$title = AppCore::Web::Common::load_template($title)->output if $title =~ /%%/;
							push @nav_path, 
							{
								title => $title,
								url   => $page->url,
								current => $page->url eq $page_obj->url,
							};
						}
					}
				}
				
				$subnav->{nav_path} = \@nav_path;
				
				#print STDERR "subnav dump: ".Dumper($subnav);
			}
			
			$SubnavCache{$url} = $subnav;
		}
		
		return $subnav;
	}

	sub output
	{
		my $self       = shift;
		my $page_obj   = shift || undef;
		my $r          = shift || $self->{response};
		my $view_code  = shift || $self->{view_code};
		my $parameters = shift || {};
		
		my $tmpl = $self->load_template('basic.tmpl');
		
		$self->auto_apply_params($tmpl,$page_obj);
		
		# load_template() automatically adds this template parameter in to your template:
		#$tmpl->param(modpath => join('/', AppCore::Config->get("WWW_ROOT"), 'mods', __PACKAGE__));
		
		#$r->output($page_obj->content);
		$r->output($tmpl); #->output);
		
		return $r;
	};
	
	
	use AppCore::Common;
	sub auto_apply_params
	{
		my ($self,$tmpl,$page_obj) = @_;
		
		#timemark("AAP - start");
		if(!$self->apply_page_obj($tmpl,$page_obj))
		{
			#timemark("AAP - no page obj, now basic");
			$self->apply_basic_data($tmpl,$page_obj);
			#timemark("AAP - basic done");
		}
		
		#timemark("AAP - app done");
		$tmpl->param(nav_url_from => $ENV{HTTP_REFERER});
		
	}
	
	sub apply_basic_data
	{
		my ($self,$tmpl,$page_obj) = @_;
		
		#print STDERR "apply_basic_data for $page_obj\n";
		#timemark("ABD start [$page_obj]");
		my $blob = (blessed $page_obj && $page_obj->isa('HTML::Template')) ? $page_obj->output : $page_obj;
		#timemark("ABD done output");
		my @titles = $blob=~/<title>(.*?)<\/title>/g;
		#$title = $1 if !$title;
		@titles = grep { !/\$/ } @titles;
		
		#timemark("ABD done titles");
		
		my $pgdat = {};
		$pgdat->{page_title}	= shift @titles;
		$pgdat->{page_content}	= $blob;
		
		my $r = $self->{response};
		if($r && $r->{page_obj})
		{
			my $subnav = $self->load_subnav($r->{page_obj});
			
			#timemark("ABD done load subnav");
			#die Dumper $subnav;
			
			$subnav = $self->add_breadcrumbs($subnav);
			
			#die Dumper $subnav;

			#timemark("ABD done breadcrumb list prep");
			$pgdat->{$_} = $subnav->{$_} foreach keys %$subnav;
		}
		else
		{
			$pgdat->{nav_path} = $self->breadcrumb_list->list;
			#die Dumper $self->breadcrumb_list->list;
			#timemark("ABD just get breadcrumbs");
		}
			
		#timemark("ABD before page.tmpl");
		eval
		{
			my $page_tmpl = $self->load_template('page.tmpl');
			if($page_tmpl)
			{
				$page_tmpl->param($_ => $pgdat->{$_}) foreach keys %$pgdat;
				$pgdat->{page_content} = $page_tmpl->output;
			}
		};
		#timemark("ABD after page.tmpl");
		
		$tmpl->param($_ => $pgdat->{$_}) foreach keys %$pgdat;
		
		#print STDERR "pgdat final: ".Dumper($pgdat);
		
		#timemark("ABD tmpl->param calls done");
		
	}
	
	sub add_breadcrumbs
	{
		my $self = shift;
		my $subnav = shift;
		
		# Integrate any page-specified breadcrumbs onto the end of the list
		my @list = @{ $self->breadcrumb_list->list || [] };
		if(@list)
		{
			$subnav = clone( $subnav );
			
			my @tmp = @{$subnav->{nav_path} || []};
			push @tmp, @list;
			
			my @final;
			my $last;
			foreach my $item (@tmp)
			{
				next if $last && $item->{url} eq $last->{url};
				$last = $item;
				$item->{current} = 0;
				push @final, $item;
			}
			$final[$#final]->{current} = 1 if @final;
			
			$subnav->{nav_path} = \@final;
		}
		
		return $subnav;
	}
	
	sub load_template
	{
		my $self = shift;
		my $file = shift;
		my $pkg  = ref $self;
		my $tmpl = undef;

		my $file_root = AppCore::Config->get('WWW_DOC_ROOT') . AppCore::Config->get('WWW_ROOT');
		$file_root .= '/' if substr($file_root, -1, 1) ne '/';

		my $DEBUG = 0;
		if($pkg ne 'Content::Page::ThemeEngine')
		{
			my $tmp_file_name = $file_root . 'mods/'.$pkg.'/tmpl/'.$file;
			print STDERR __PACKAGE__."::load_template(): [1] Try load: $tmp_file_name\n" if $DEBUG;
			if($file !~ /^\// && -f $tmp_file_name)
			{
				$tmpl = AppCore::Web::Common::load_template($tmp_file_name);
			}
			else
			{
				print STDERR __PACKAGE__."::load_template(): [1] Template file didnt exist: $tmp_file_name\n" if $DEBUG;
			}
		}
		
		if(!$tmpl)
		{
			my $tmp_file_name = $file_root .'mods/Content/tmpl/'.$file;
			print STDERR __PACKAGE__."::load_template(): [2] Try load: $tmp_file_name\n" if $DEBUG;
			if($file !~ /^\// && -f $tmp_file_name)
			{
				$tmpl = AppCore::Web::Common::load_template($tmp_file_name);
			}
			else
			{
				print STDERR __PACKAGE__."::load_template(): [2] Template file didnt exist: $tmp_file_name\n" if $DEBUG;
			}
		}
		
		
		if(!$tmpl)
		{
			my $tmp_file_name = $file_root .'tmpl/'.$file;
			print STDERR __PACKAGE__."::load_template(): [3] Try load: $tmp_file_name\n" if $DEBUG;
			if($file !~ /^\// && -f $tmp_file_name)
			{
				$tmpl = AppCore::Web::Common::load_template($tmp_file_name);
			}
			else
			{
				print STDERR __PACKAGE__."::load_template(): [3] Template file didnt exist: $tmp_file_name\n" if $DEBUG;
			}
		}
		
		
		if(!$tmpl)
		{
			$tmpl = AppCore::Web::Common::load_template($file);
		}
		
		if($tmpl)
		{
			$tmpl->param(appcore => join('/', AppCore::Config->get("WWW_ROOT")));
			$tmpl->param(modpath => join('/', AppCore::Config->get("WWW_ROOT"), 'mods', $pkg));
			$tmpl->param($_ => $self->{params}->{$_}) foreach keys %{$self->{params}};
			$tmpl->param(mainnav      => $self->load_nav); 
			
			my $user = AppCore::Common->context->user;
			$tmpl->param(is_admin  => $user && $user->check_acl(['ADMIN']));
			$tmpl->param(is_mobile => AppCore::Common->context->mobile_flag);
			$tmpl->param(website_name => AppCore::Config->get('WEBSITE_NAME'));
		}
	
		return $tmpl;
	}
	
	sub get_template_path
	{
		my $self = shift;
		my $file = shift;
		my $pkg = ref $self ? ref $self : $self;
		
		my $tmp_file_name = 'mods/'.$pkg.'/tmpl/'.$file;
		return -f $tmp_file_name ?  $tmp_file_name : $file;
	}
	
	# Subclasses can override this method to remap a template to a different filename
	# just before the template is loaded. This is called in AppCore::Web::Module::get_template()
	sub remap_template
	{
# 		my $class = shift;
# 		my $requesting_package = shift;
# 		my $requested_theme_file = shift;
		return undef; 
	}
	
	# Subclasses can override this method to remap the entire URL - this is called
	# very early in the dispatching process - before any module is called. Called from
	# AppCore::Web::DispatchCore::process()
	sub remap_url
	{
# 		my $class = shift;
# 		my $requested_url = shift;
	}
};

1;
