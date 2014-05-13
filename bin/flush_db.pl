#!/usr/bin/perl
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::Web::Module;

# ## System packages that don't have a home in a module
# use AppCore::EmailQueue;
# use AppCore::User;
# 
# AppCore::EmailQueue->apply_mysql_schema;
# AppCore::User->apply_mysql_schema;
# 
# # Module-specific classes
# my $module_cache = AppCore::Web::Module::module_name_lut();
# 
# foreach my $data (values %$module_cache)
# {
# 	if($data->{obj}->can('apply_mysql_schema'))
# 	{
# 		$data->{obj}->apply_mysql_schema();
# 	}
# }
# 
# 

# Use this call to automatically create the database in DB_NAME prior to any other modules being loaded
BEGIN {
	my $db = $AppCore::Config::DB_NAME;
	print "Making sure db '$db' exists...\n";
	AppCore::DBI->auto_new_dbh($db);
};

## System packages that don't have a home in a module
use AppCore::EmailQueue;
use AppCore::User;
use AppCore::Web::Form;

print STDERR "$0: Processing EmailQueue, Content, User...\n";
AppCore::EmailQueue->apply_mysql_schema;
AppCore::User->apply_mysql_schema;
AppCore::Web::Form::ModelMeta->apply_mysql_schema;

# use Content;
# Content->apply_mysql_schema;

# Module-specific classes
print STDERR "$0: Loading module_name_lut\n";
my $module_cache = AppCore::Web::Module::module_name_lut();

my %ignore = %{$AppCore::Config::IGNORE_MODS || {}};

print STDERR "$0: Processing module_cache...\n";
MODULE_NAME: foreach my $data (values %$module_cache)
{
	#next if $data =~ /^Theme/ && $data ne $AppCore::Config::THEME_MODULE;
	my $name = ref($data->{obj});
	foreach my $key (keys %ignore)
	{
		#print "\t Ignore test: $key/$name\n";
		next MODULE_NAME if $name =~ /^$key/; # || $name eq $key;
	}
	
	if($data->{obj}->can('apply_mysql_schema'))
	{
		print STDERR "$0: Processing class '$name'\n";
		$data->{obj}->apply_mysql_schema();
	}
}
