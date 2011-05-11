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
	
	# Path in the server's file system to the document root of the websrver
	$WWW_DOC_ROOT = '/opt/httpd-2.2.17/htdocs';
	# Path in the webserver's URL space (and relative to WWW_DOC_ROOT) where
	# the appcore distribution lives
	$WWW_ROOT     = '/appcore';
	
	# The absolute path in the server's file system where appcore lives
	$APPCORE_ROOT = $WWW_DOC_ROOT . $WWW_ROOT;
	
	# Database configuration
	$DB_HOST = '127.0.0.1';
	$DB_USER = 'root';
	$DB_PASS = 'testsys';
	$DB_NAME = 'appcore';
	
	# Users's database config
	$USERS_DBNAME = $DB_NAME;
	$USERS_DBTABLE = 'users';
	
	# TODO is this even needed now that User is a top-level module?
	$LOGIN_URL = '/user/login';
	
	# TODO is this redundant to WEBSITE_SERVER?
	$DOMAIN = 'example.com';
	
	# TODO is this redudant to ADMIN_EMAILS?
	# This is displayed in error() messages
	$WEBMASTER_EMAIL = 'josiahbryan@gmail.com';
	
	# Prefunctory at best...does what it says...
	$MOBILE_REDIR = 1;
	$MOBILE_URL = '/m';
	
	# Names use for user correspondance and other system-generated user-facing pages/content
	$WEBSITE_NAME = 'PHC Beta Site';
	$WEBSITE_NOUN = 'PHC Beta';
	
	# When neededing a globally-absolute URL, what server should we prefix?
	# Normally, URLs created are local URLs, absolute to the server, but not including the server.
	# The globally absolute URLs are normally only used for things such as emails, etc
	$WEBSITE_SERVER = 'http://beta.mypleasanthillchurch.org';
	
	# Emails to send new user notifications to, etc
	@ADMIN_EMAILS = qw/
		josiahbryan@gmail.com
	/;
	
	# Where to redirect user after signon
	$WELCOME_URL = '/welcome';
	
	# Prevent users from send arbitrarily long URLs and consuming resources
	$MAX_URL_DEPTH = 25; 
	
	# If apache is rewriting the dispatcher away, this will be empty.
	# If there is some path prefix to where the appcore starts, then put that in here.  
	$DISPATCHER_URL_PREFIX = '';
	
	
	###########################################
	# Facebook Connect
	# The User module can integrate with Facebook for authentication and automatic user creation.
	 
	# Your facebook AppID for login integration
	$FB_APP_ID     = '192357267468389';
	
	# Read your App Secret from a local file that is NOT stored in a public source control repo
	my $fb_secret_file = $WWW_DOC_ROOT . $WWW_ROOT . '/fb_app_secret.txt';
	$FB_APP_SECRET = `cat $fb_secret_file` if -f $fb_secret_file;
	$FB_APP_SECRET =~ s/[\r\n]//g;  # remove newlines read from cat/shell command  
	
	###########################################
	# CSSX tags (<a:cssx src="..."/>) specify CSS files to be included that need template variable replacements (%%...%%)
	# The processed files are optionally combined into one, compressed, and stored in the $APPCORE/cssx/ directory, and automatically
	# recompiled if the original .css file ever changes/
	#
	# The options below control the processing of the files included via <a:cssx/> tags...
	$ENABLE_CSSX_IMAGE_URI = 0;	# Replace url()'s to images with data: URI's (not recommended as IE doesnt support yet)
	$ENABLE_CSSX_MOBILE_IMAGE_URI = 1; # If its a mobile browser, go ahead and replace url()s in CSS with data: URI's, even if $ENABLE_CSSX_IMAGE_URI is 0  
	$ENABLE_CSSX_IMPORT    = 1;	# Process @import statements that refer to local files by creating a new CSS file that has both the original CSS and the imported CSS 
	$ENABLE_CSSX_COMBINE   = 1;	# Combine multiple local CSS includes into a single file (optionally compress with YUI, below)
	$ENABLE_INPAGE_CSS_COMBINE = 1; # Combine in-page <style></style> blocks into a single block
					# NOTE: $ENABLE_INPAGE_CSS_COMBINE only works if $ENABLE_CSSX_COMBINE is also enabled 
	$ENABLE_NON_CSSX_COMBINE = 1;	# Not implemented yet ...
	
	# Process CSSX (above) thru csstidy if path given and the file in $USE_CSS_TIDY exists (-f) 
	$USE_CSS_TIDY = '/opt/httpd-2.2.17/htdocs/appcore/csstidy/release/csstidy/csstidy';
	$CSS_TIDY_SETTINGS = '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
	
	###########################################
	# AppCore can automatically combine local <script src='...'> includes into a single file, and optionally compress the result via YUI
	# We can also grab all the <script></script> blocks in the page into a single (optionally compressed and cached) block at the end of the page.. 
	$ENABLE_JS_COMBINE     = 1;	# Combine local <script src='...'> includes (e.g. that start with "/") into a single file (and process %%variable%% and url() constructs)
	$ENABLE_JS_REORDER     = 1;	# Reorder <script> blocks based on index atribute to below <script> includes
	$ENABLE_JS_REORDER_YUI = 0;	# Run the combined block of scripts in that page thru YUI before inclusion
	
	# Compress CSSX with YUI compressor if the .jar in $USE_YUI_COMPRESS exists  
	$USE_YUI_COMPRESS = 'java -jar /opt/httpd-2.2.17/htdocs/appcore/yuicomp/yuicompressor-2.4.6/build/yuicompressor-2.4.6.jar';
	$YUI_COMPRESS_SETTINGS = '';

	###########################################
	# Roundrobin "CDN" replacements
	# AppCore::Web::Result->output will optionally replace the url()'s in CSSX files,
	# <link> hrefs (for css), <script> srcs (for javascript), and <img> srcs with a 
	# server name from the list below. Method for server name choice is given below
	
	$CDN_MODE = 'hash';		# Valid options are mod, hash, and rr
					# 'mod' takes the modula of the md5 of the file and the number of servers below to get the index of the server to use
					# 'rr' does a round-robin (rotating index) server name each time a server is requested
					# 'hash' checks to see if the file has been used on the CDN before - if so, uses same server. If not, does 'rr' and stores the result
	
	$CDN_HASH_FILE = '/tmp/appcore-cdn.storable'; # Uses Storable freeze/thaw to write hash
	$CDN_HASH_FORCEWRITE_COUNT = 0; # If >0, every X calls to cdn_url() will write out the hash file to disk if $CDN_MODE is 'hash'.
					# cdn_url() automatically writes the hash file on cache miss (e.g. if the url requested was not already in the hash)
					# cdn_url() checks the mod time of the hash prior to each call and reloads the hash from disk of modified outside of the current process.
					# This allows for multiple server instances to share the same hash file (along with proper locking) so that the same URL gets the same
					# CDN server regardless of the server instance processing the URL. 
	
	$ENABLE_CDN_FQDN_ONLY = 1;	# Only do CDN replacements if requested from $WEBSITE_SERVER 
					# This helps when testing from a development server (e.g. localhost, etc.) by not doing CDN replacements if they won't work on the current server.
	$ENABLE_CDN_CSSX_URL = 1;	# Controls replacement of url() properties in CSSX files
	$ENABLE_CDN_CSS  = 1;		# Controls replacement of the href attrib of <link> tags for CSS inclusion
	$ENABLE_CDN_IMG  = 1;		# Controls replacement of the src attrib of <img> tags
	$ENABLE_CDN_JS   = 1;		# Controls replacement of the src attrib of <script> tags
	$ENABLE_CDN_MACRO = 1;		# Enable ${CDN} or ${CDN:...} replacement (or $(CDN:...)) - the latter keeps the CDN server the same for the url in the '...' - the first (${CDN}) just gives a random host from below
	
	# ${tmpl2jq:<file>} reads the given <file> and changes any tmpl-style tags (%%var%%) to jquery tmpl style (${var}) and inserts the new text into the output 
	$ENABLE_TMPL2JQ_MACRO = 1;
	
	# Quoting from: http://yuiblog.com/blog/2007/04/11/performance-research-part-4/
	# Our rule of thumb is to increase the number of parallel downloads by using at least two, but no more than four hostnames.
	
	# Therefore, limit the number of @CDN_HOSTS to 3 or 4 hosts
	# Make sure to include the initial (main) host (if reasonable)
	# because this saves 20-150ms on DNS lookup time
	
	@CDN_HOSTS = qw/
		beta.mypleasanthillchurch.org
		cdn1.mypleasanthillchurch.org
		cdn2.mypleasanthillchurch.org
		cdn3.mypleasanthillchurch.org
		
	/; 
	#	
	#	cdn4.mypleasanthillchurch.org
	#	cdn5.mypleasanthillchurch.org
	#/;
	
	###########################################
	# Module-specific configuration
	
	$BOARDS_SHORT_TEXT_LENGTH    = 300;  # characters
	$BOARDS_POST_PAGE_LENGTH     = 10;   # posts
	$BOARDS_POST_PAGE_MAX_LENGTH = 100;  # posts
	
	
};

1;