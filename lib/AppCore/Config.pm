## This file must start with 'package AppCore::Config;' and end with a '1' and a newline 
package AppCore::Config;
BEGIN
{
	$DEFAULT_MODULE = '/';
	
	# By convention, all theme modules start with 'Theme'
	$THEME_MODULE   = 'ThemePHC';
	
	# If this is true, then when user requests '/favicon.ico',
	# it will be redirected to /appcore/mods/$THEME_MODULE/favicon.ico
	# $USE_THEME_FAVICON = 1;
	# If set to a string value, redirect will be to:
	# /appcore/mods/$THEME_MODULE/$USE_THEME_FAVICON
	$USE_THEME_FAVICON = 'favicon-trans.ico';
	
	$WWW_DOC_ROOT = '/opt/httpd-2.2.17/htdocs';
	$WWW_ROOT     = '/appcore';
	
	$APPCORE_ROOT = $WWW_DOC_ROOT . $WWW_ROOT;
	
	$DB_HOST = '127.0.0.1';
	$DB_USER = 'root';
	$DB_PASS = 'testsys';
	$DB_NAME = 'appcore';
	
	$USERS_DBNAME = $DB_NAME;
	$USERS_DBTABLE = 'users';
	
	$LOGIN_URL = '/user/login';
	
	$DOMAIN = 'example.com';
	
	$WEBMASTER_EMAIL = 'josiahbryan@gmail.com';
	
	$MOBILE_REDIR = 1;
	$MOBILE_URL = '/m';
	
	$WEBSITE_NAME = 'PHC Beta Site';
	$WEBSITE_NOUN = 'PHC Beta';
	
	$WEBSITE_SERVER = 'http://beta.mypleasanthillchurch.org';
	
	@ADMIN_EMAILS = qw/
		josiahbryan@gmail.com
	/;
	
	$WELCOME_URL = '/welcome';
	
	# If apache is rewriting the dispatcher away, this will be empty.
	# If there is some path prefix to where the appcore starts, then put that in here.  
	$DISPATCHER_URL_PREFIX = '';
	
	$FB_APP_ID     = '192357267468389';
	$FB_APP_SECRET = `cat fb_app_secret.txt`; # read from file so its not saved in subversion!
	$FB_APP_SECRET =~ s/[\r\n]//g;  # remove newlines read from cat/shell command  
	
	$ENABLE_CSSX_IMAGE_URI = 0;
	$ENABLE_CSSX_IMPORT    = 1;
	$ENABLE_CSSX_COMBINE   = 1;
	$ENABLE_NON_CSSX_COMBINE = 1;
	
	$USE_CSS_TIDY = '/opt/httpd-2.2.17/htdocs/appcore/csstidy/release/csstidy/csstidy';
	$CSS_TIDY_SETTINGS = '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
	
	$USE_YUI_COMPRESS = 'java -jar /opt/httpd-2.2.17/htdocs/appcore/yuicomp/yuicompressor-2.4.6/build/yuicompressor-2.4.6.jar';
	$YUI_COMPRESS_SETTINGS = '';

	# Prevent users from send arbitrarily long URLs and consuming resources
	$MAX_URL_DEPTH = 25; 
	
	### Roundrobin CDN replacements
	# AppCore::Web::Result->output will optionally replace the url()'s in CSSX files,
	# <link> hrefs (for css), <script> srcs (for javascript), and <img> srcs with a 
	# server name from the list below. Method for server name choice is given below
	
	$CDN_MODE = 'hash';		# Valid options are mod, hash, and rr
					# 'mod' takes the modula of the md5 of the file and the number of servers below to get the index of the server to use
					# 'rr' does a round-robin (rotating index) server name each time a server is requested
					# 'hash' checks to see if the file has been used on the CDN before - if so, uses same server. If not, does 'rr' and stores the result
	
	$CDN_HASH_FILE = '/tmp/appcore-cdn.storable'; # Uses Storable freeze/thaw to write hash 
	
	$ENABLE_CDN_FQDN_ONLY = 1;	# Only do CDN replacements if requested from $WEBSITE_SERVER 
					# This helps when testing from a development server (say, localhost!) by not doing CDN replacements if they won't work on the current server.
	$ENABLE_CDN_CSSX_URL = 1;	# Controls replacement of url() properties in CSSX files
	$ENABLE_CDN_CSS  = 1;		# Controls replacement of the href attrib of <link> tags for CSS inclusion
	$ENABLE_CDN_IMG  = 1;		# Controls replacement of the src attrib of <img> tags
	$ENABLE_CDN_JS   = 1;		# Controls replacement of the src attrib of <script> tags
	@CDN_HOSTS = qw/
		cdn1.mypleasanthillchurch.org
		cdn2.mypleasanthillchurch.org
		cdn3.mypleasanthillchurch.org
		cdn4.mypleasanthillchurch.org
		cdn5.mypleasanthillchurch.org
	/;
};

1;