# Package: AppCore::Web::Module
# Static functions for enumeration and loading of AppCore::Web::Modules.

package AppCore::Web::Module;
{
	
	use strict;
	use Data::Dumper;
	
	use AppCore::Common;
	
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
		my $module_name = shift;
		
		return $mod_ref_cache{$module_name} if $mod_ref_cache{$module_name};
		
		my $dir_base   = module_root_dir($module_name);
		
		#my $class_base = module_base_package($module_name);
		
		my $pkg_file = $dir_base   .'/'.$module_name.'.pm';
		
		require $pkg_file;
		
		if($module_name->can('new'))
		{
			return $mod_ref_cache{$module_name} = $module_name->new;
		}
		else
		{
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
		if(@_)
		{
			my %map = map {$_=>1} @_;
			$Method_Lists_Cache{$pkg} = \%map;
		}
		return $Method_Lists_Cache{$pkg};
	}
	
	sub get_template
	{
		my $self = shift;
		my $file = shift;
		
		my $pkg = $self;
		$pkg = ref $pkg if ref $pkg;
		
		my $tmp_file_name = 'mods/'.$pkg.'/tmpl/'.$file;
		if($file !~ /^\// && -f $tmp_file_name)
		{
			my $tmpl = AppCore::Web::Common::load_template($tmp_file_name);
			$tmpl->param(appcore => join('/', $AppCore::Config::WWW_ROOT));
			$tmpl->param(modpath => join('/', $AppCore::Config::WWW_ROOT, 'mods', $pkg));
			$tmpl->param(binpath => join('/', $AppCore::Config::DISPATCHER_URL_PREFIX, lc $pkg));
			return $tmpl;
		}
		else
		{
			print STDERR "Template file didnt exist: $tmp_file_name\n";
		}
		
		return AppCore::Web::Common::load_template($file);
	}
	
	sub module_url
	{
		my $pkg = shift;
		my $suffix = shift || '';
		my $include_server = shift || 0;
		$pkg = ref $pkg if ref $pkg;
		my $url = join('/', $AppCore::Config::DISPATCHER_URL_PREFIX, lc $pkg, $suffix);
		if($include_server)
		{
			return $AppCore::Config::WEBSITE_SERVER . '/' . $url;
		}
		
		return $url;
	}
	
};
1;
