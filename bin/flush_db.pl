#!/usr/bin/perl
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;

AppCore::User->apply_mysql_schema;

my $module_cache = AppCore::Web::Module::module_name_lut();

foreach my $data (values %$module_cache)
{
	if($data->{obj}->can('apply_mysql_schema'))
	{
		$data->{obj}->apply_mysql_schema();
	}
}
