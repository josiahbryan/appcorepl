#!/usr/bin/perl
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::Web::Module;

## System packages that don't have a home in a module
use AppCore::EmailQueue;
use AppCore::User;

AppCore::EmailQueue->apply_mysql_schema;
AppCore::User->apply_mysql_schema;

# Module-specific classes
my $module_cache = AppCore::Web::Module::module_name_lut();

foreach my $data (values %$module_cache)
{
	if($data->{obj}->can('apply_mysql_schema'))
	{
		$data->{obj}->apply_mysql_schema();
	}
}


