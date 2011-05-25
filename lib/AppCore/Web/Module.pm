# Package: AppCore::Web::Module
# Static functions for enumeration and loading of AppCore::Web::Modules.

package AppCore::Web::Module;
{
	
	use strict;
	use Data::Dumper;
	
	use AppCore::Common;
	
	# Required to access Content::Page::Controller->theme->remap_template()
	use Content::Page;
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/Dumper 
		bootstrap
		enum_modules
		module_name_lut
		module_base_package
		module_root_dir
		module_meta
		MODULE_NAME
		$MODULE_NAME
	/;
	
	
	### Group: Static Functions
	### Static functions for enumeration and loading
	###
	
	
	
	my %mod_dir_base_cache;
	my %mod_pkg_base_cache;
	my %mod_parent_cache;
	
	# Function: module_base_package
	# Not exported by default - normally rather private - only really used by bootstrap right now.
	# Can be called, just need to specify full package
	sub module_base_package 
	{ 
		my $mod = shift; 
		my $parent = $mod_parent_cache{$mod};
		
		return SYS_PACKAGE_BASE.'::' . $mod; #($parent ? $parent.'::' : '') . $mod;
	}
	
	#sub module_root_dir     { my $mod = shift; join '/',  $mod_dir_base_cache{$mod}, $mod }
	
	sub module_root_dir 
	{ 
		my $mod = shift;# || MODULE_NAME();
		#my $parent = $mod_parent_cache{$mod};
		
		#$mod =~ s/^${parent}:://g;
		#($parent ? $parent.'/modules/' : '') . 
		return SYS_PATH_MODULES.'/' . $mod;
	}
	
	
	# Function: bootstrap($module_name,[$interface_class],[$return_mod_pk])
	# Static function.
	# Arguments:
	#   Loads module AppCore::Web::Module::$module_name::Meta using 'require'
	#   If $interface_class is specified, module AppCore::Web::Module::$module_name::$interface_class is also loaded with 'require'.
	# Returns:
	#   If $return_mod_pk is false (it defaults false) or $interface_class is not given, bootstrap will return
	#   a string containing AppCore::Web::Module::$module_name::Meta, otherwise if $return_mod_pk is a true value AND $interface_class
	#   is not undef, bootstrap will return AppCore::Web::Module::$module_name::$interface_class.
	# To catch errors when modules are loaded (parse errors, etc) be sure to wrap bootstrap() in an eval {}; block
	# and check $@ on return - otherwise perl will die on parse errors when the modules are require'd.
	
	my %mod_ref_cache;
	
	sub bootstrap
	{
		shift if $_[0] eq __PACKAGE__;
		
		my $module_name = shift;
		
		#print STDERR "bootstrap($module_name): mark1\n";
		return $mod_ref_cache{$module_name} if defined $mod_ref_cache{$module_name};
		
		#print STDERR "bootstrap($module_name): mark2\n";
		
		my @parts = split /::/, $module_name;
		my $first_pkg = $parts[0];
		
		shift @parts if @parts > 1;
		
		my $dir_base   = module_root_dir($first_pkg);
		
		#my $class_base = module_base_package($module_name);
		
		my $pkg_file = join('/', $dir_base, @parts) . '.pm';
		
		#print STDERR "Attempting to load: $pkg_file, exists? ".((-f $pkg_file)?1:0)."\n";
		undef $@;
		
		eval { require $pkg_file; } if -f $pkg_file;
		
		print STDERR "Error loading $pkg_file: $@" if $@;
		
		if($module_name->can('new'))
		{
			my $ref = $module_name->new;
			#print STDERR "bootstrap($module_name): mark3, ref:'$ref'\n";
			return $mod_ref_cache{$module_name} = $ref;
		}
		else
		{
			#print STDERR "bootstrap($module_name): mark4\n";
			$mod_ref_cache{$module_name} = $module_name;
			return $module_name;
		}
	}
	
	
	# Variable: $mod_list_cache
	# Private cache
	my $mod_list_cache; # private
	# Function: enum_modules()
	# No arguments.
	# Static function.
	# Returns arrayref containing {module=>$module_name,meta=>$meta_hashref}, where the meta hashref is the value returned by
	# the modules Meta->meta function.
	sub enum_modules
	{
		return $mod_list_cache if $mod_list_cache;
		
		local $_;
		opendir(DIR,SYS_PATH_MODULES);
		my @list = grep { !/^\./ } readdir DIR;
		closedir(DIR);
		
		my @data = map 
		{
			{
				base   => SYS_PATH_MODULES,
				module => $_, 
				obj    => bootstrap($_)
			} 
		} @list;
		
		
		$mod_list_cache = \@data;
		
		return $mod_list_cache;
	
	}
	
	# Function: module_name_lut()
	# Static function.
	# No arguments.
	# Compose a hash of app names as lowercase strings referencing the app data in enum_modules, above.
	my $module_lut_cache;
	sub module_name_lut
	{
		return $module_lut_cache if $module_lut_cache;
		
		$module_lut_cache = { map { lc $_->{module} => $_ } @{ enum_modules() } };
		
		return $module_lut_cache;
	}
	
# 	# Function: module_meta
# 	# Static utility function
# 	# param: $module_name - Name of the module to retrieve
# 	# returns: AppCore::Web::Module::Meta instance for referenced package
# 	sub module_meta
# 	{
# 		my $module_name = shift;
# 		my $lut = module_name_lut();
# 		my $proper_name = $lut->{lc $module_name}->{module};
# 		if(!$proper_name)
# 		{
# 			$@ = "Unknown module '$module_name'";
# 			#warn "module_meta: $@";
# 			return undef;
# 		}
# 		
# 		my $pk = bootstrap($proper_name);
# 		return $pk->meta;
# 	}
	
	# Function: MODULE_NAME
	# Return the EAS module name of the caller
	sub MODULE_NAME
	{
		## USE CALLER TO FIND BASEREF
		my ($pkg,$file,$line) = caller;
		my $x = 1;
		while($file && $pkg !~ /^AppCore::Web::Module::/)
		{
			($pkg,$file,$line) = caller($x++);
		};
		
	
		my $mod = '';
		if($pkg =~ /^AppCore::Web::Module::(.*)::([^:]*)$/)
		{
			#$path = AppCore::Web::Module::module_root_dir($1) .'/tmpl';
			#print STDERR "name=$name, path=$path, pkg=$pkg\n";
			$mod = $1;
		}
		
		return $mod;
	
	}
	
	our %Method_Lists_Cache;
	
	sub WebMethods
	{
		my $pkg = shift;
		# Want to use the typename as the $pkg key, not the instance ID
		$pkg = ref $pkg if ref $pkg;
		#($pkg) = $pkg =~ /^([^\:]+):/ if $pkg =~ /::/;
		if(@_)
		{
			#print STDERR "WebMethods: pkg: '$pkg', list: ".join('|', @_)."\n";
			
			my %map = map {$_=>1} @_;
			$Method_Lists_Cache{$pkg} = \%map;
		}
		return $Method_Lists_Cache{$pkg} || {};
	}
	
	our %ModpathCache;
	
	sub modpath
	{
		my $pkg = shift;
		
		$pkg = ref $pkg if ref $pkg;
	
		return $ModpathCache{$pkg} = shift if @_;
		return $ModpathCache{$pkg}         if $ModpathCache{$pkg};
		
		my @parts = split /::/, $pkg;
		my $first_pkg = shift @parts;
		
		my $tmp = join('/', $AppCore::Config::WWW_ROOT, 'mods', $first_pkg);
		$ModpathCache{$pkg} = $tmp;
		
		return $tmp;
	}
	
	our %BinpathCache;
	sub binpath
	{
		my $pkg = shift;
		
		$pkg = ref $pkg if ref $pkg;
		
		return $BinpathCache{$pkg} = shift if @_;
		return $BinpathCache{$pkg}         if $BinpathCache{$pkg};
		
		# Binpath not cached, build it up automatically
		#($pkg) = $pkg =~ /^([^\:]+):/ if $pkg =~ /::/;
		#$pkg =~ s/::/\//g;
		$pkg = lc $pkg;
		$pkg =~ s/::/\//g;
		
		my $tmp = join('/', $AppCore::Config::DISPATCHER_URL_PREFIX, $pkg);
		$BinpathCache{$pkg} = $tmp;
		
		return $tmp;
	}
	
	sub get_template
	{
		my $self = shift;
		my $file = shift;
		
		my $pkg = $self;
		$pkg = ref $pkg if ref $pkg;
		
		# Give the current theme an opportunity to remap the template into something different if desired
		my $abs_file = Content::Page::Controller->theme->remap_template($pkg,$file);
		#print STDERR "get_template: 0: $abs_file\n";
		if(!$abs_file || !-f $abs_file)
		{
			#($pkg) = $pkg =~ /^([^\:]+):/ if $pkg =~ /::/;
			#$pkg =~ s/::/\//g;
			my @parts = split /::/, $pkg;
			my $first_pkg = shift @parts;
			@parts = lc $_ foreach @parts;
			push @parts, $file;
			
			$abs_file = 'mods/'.$first_pkg.'/tmpl/'.join('/', @parts);
			#print STDERR "get_template: 1: $abs_file\n";
		}
		
		if(!$abs_file || !-f $abs_file)
		{
			#($pkg) = $pkg =~ /^([^\:]+):/ if $pkg =~ /::/;
			#$pkg =~ s/::/\//g;
			my @parts = split /::/, $pkg;
			my $first_pkg = shift @parts;
			#@parts = lc $_ foreach @parts;
			#push @parts, $file;
			
			$abs_file = 'mods/'.$first_pkg.'/tmpl/'.$file;
			#print STDERR "get_template: 2: $abs_file\n";
		}
		
		if($file !~ /^\// && -f $abs_file)
		{
			my $tmpl = AppCore::Web::Common::load_template($abs_file);
			$tmpl->param(appcore => join('/', $AppCore::Config::WWW_ROOT));
			$tmpl->param(modpath => $self->modpath);
			$tmpl->param(binpath => $self->binpath);
			my $user = AppCore::Common->context->user;
			$tmpl->param(is_admin => $user && $user->check_acl(['ADMIN']));
			$tmpl->param(is_mobile => AppCore::Common->context->mobile_flag);
			return $tmpl;
		}
		else
		{
			print STDERR "Template file didnt exist: $abs_file\n";
		}
		
		return AppCore::Web::Common::load_template($file);
	}
	
	sub module_url
	{
		my $pkg = shift;
		my $suffix = shift || '';
		my $include_server = shift || 0;
		my $url = join('/', $pkg->binpath, $suffix);
		if($include_server)
		{
			return $AppCore::Config::WEBSITE_SERVER . $url;
		}
		
		return $url;
	}
	
	sub dispatch
	{
		my $class = shift;
		$class = ref $class if ref $class;
		
		my $request  = shift;
		my $response = shift;
		
		my $receiver_class = shift || $class;
		
		my $mod_obj = bootstrap($receiver_class);
		
		my $method;
		
		#print STDERR "Module::dispatch: class $class, rx $receiver_class, mod_obj '$mod_obj', WebMethods: ".$mod_obj->WebMethods.", next path:".$request->next_path."\n";
		if($request->next_path && 
		   $mod_obj->WebMethods->{$request->next_path} &&
		   $mod_obj->can($request->next_path))
		{
			$method = $request->shift_path;
			$request->push_page_path($method);
		}
		elsif($mod_obj->can('DISPATCH_METHOD'))
		{
			$method = $mod_obj->DISPATCH_METHOD;
		}
		else
		{
			$method = 'main';
		}
		
		if($mod_obj->can($method))
		{
			$response = $mod_obj->$method($request,$response);
		}
		else
		{
			print STDERR "Cannot dispatch to $mod_obj / $method\n";
			$response->error(404, "Module $mod_obj exists, but method '$method' is not valid."); 
		}
		
		return $response;
	}
};
1;
