## This file must start with 'package AppCore::Config;' and end with a '1' and a newline 
package AppCore::Config;
BEGIN
{
	$DEFAULT_MODULE = '/';
	
	# By convention, all theme modules start with 'Theme'
	$THEME_MODULE   = 'ThemePHC';
	
	# If this is true, then when user requests '/favicon.ico',
	# it will be redirected to /appcore/mods/$THEME_MODULE/favicon.ico
	$USE_THEME_FAVICON = 1;
	
	$WWW_DOC_ROOT = '/opt/httpd-2.2.17/htdocs';
	$WWW_ROOT     = '/appcore';
	
	$APPCORE_ROOT = $WWW_DOC_ROOT . $WWW_ROOT;
	
	$DB_HOST = '127.0.0.1';
	$DB_USER = 'root';
	$DB_PASS = 'testsys';
	$DB_NAME = 'appcore';
	
	$USERS_DBNAME = $DB_NAME;
	$USERS_DBTABLE = 'users';
	
	$LOGIN_URL = '/login';
	
	$DOMAIN = 'example.com';
	
	$WEBMASTER_EMAIL = 'josiahbryan@gmail.com';
	
	$MOBILE_REDIR = 1;
	$MOBILE_URL = '/m';
	
	$WEBSITE_NAME = 'PHC Beta Site';
	$WEBSITE_NOUN = 'PHC Beta';
	
	@ADMIN_EMAILS = qw/
		josiahbryan@gmail.com
	/;
	
	$WELCOME_URL = '/welcome';
	
	# If apache is rewriting the dispatcher away, this will be empty.
	# If there is some path prefix to where the appcore starts, then put that in here.  
	$DISPATCHER_URL_PREFIX = '';
	

};

1;