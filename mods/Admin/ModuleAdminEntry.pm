# Package: Admin::ModuleAdminEntry;
# Other modules that want to have a section in the Admin module should
# create a record with this object. Example:
#
# package MyDiscussionBoard;
# {
#     Admin::ModuleAdminEntry->register('MyDiscussionBoard::Admin');
#     # register($pkg,$title,$folder,$main) will guess the folder_name and title of the entry unless otherwise specified
#     # register can also be called register(__PACKAGE__) and it will just add '::Admin' to the end of the package name.
# } 
use strict;

package Admin::ModuleAdminEntry;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Admin Module Entry',
		class_title	=> 'Admin Module List',
		
		table		=> $AppCore::Config::PAGE_DBTABLE || 'admin_module_entries',
		
		schema	=>
		[
			{
				'field'	=> 'entryid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'package',		type	=> 'varchar(255)', }, # required
			{	field	=> 'main_method',	type	=> 'varchar(255)', null => 0, default => 'main'},
			{	field	=> 'title',		type	=> 'varchar(255)' }, # Defaults to guess_title( $first_package_part )
			{	field	=> 'folder_name',	type	=> 'varchar(255)' }, # Defaults to first part of package
		]	
	
	});
	
	sub register
	{
		my $self = shift;
		my $admin_pkg	= shift;
		my $title	= shift;
		my $folder_name	= shift;
		my $main	= shift || 'main';
		
		if($admin_pkg !~ /::/)
		{
			$admin_pkg .= '::Admin';
		}
		
		my @parts = split /::/, $admin_pkg;
		my $first_pkg = shift @parts;
		$title = AppCore::Common->guess_title($first_pkg) if !$title;
		$folder_name = lc($first_pkg) if !$folder_name;
		
		return $self->find_or_create({
			'package'	=> $admin_pkg,
			main_method	=> $main,
			title		=> $title,
			folder_name	=> $folder_name
		});
	}
	
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update(__PACKAGE__);	
	}
};
1;
