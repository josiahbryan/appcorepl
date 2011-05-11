use strict;

package AppCore::Web::DispatchCore;
{
	use HTML::Template;
	use CGI::Carp qw/fatalsToBrowser/;
	use Data::Dumper;
	
	use lib 'lib';
	use AppCore::Web::Common;
	use AppCore::Web::Module;
	use AppCore::Web::Result;
	use AppCore::Web::Request;
	use AppCore::User;
	use AppCore::AuthUtil;
	
	use HTML::Template;
	use File::Find;
	
	use Time::HiRes qw/time/;
	
	# To access ::theme()
	use Content::Page;
	
	# Read modules before starting
	sub new
	{
				
		# print STDERR "Pre-loading HTML Templates...\n";
		# find(
		# 	sub {
		# 		return unless /\.tmpl$/;
		# 		#print STDERR "   $_\n";
		# 		HTML::Template->new(
		# 					filename => "$File::Find::dir/$_",
		# 					cache => 1,
		# 				);
		# 	},
		# 	SYS_PATH_BASE .'/tmpl',
		# 	#'/another/path/to/templates/'
		# );
		
		#$ENV{MOD_FASTCGI} = 1;
	
	

		my $class = shift;
		
		my $ref = 
		{
			module_cache => AppCore::Web::Module::module_name_lut(),
		};
		
		return bless $ref, $class;
	}
	
	sub _jumpto_end { goto END_HTTP_REQUEST }


	sub error
	{
		my ($title,$text) = @_;
		
		my $ctx_ref = AppCore::Common->context;
		my $st = AppCore::Common::get_stack_trace();
		return if index($st,'(eval)') > -1;
		
		#print STDERR $st;
		print STDERR "(PID $$) [".($ctx_ref->user ? $ctx_ref->user->user."@" : "").$ENV{REMOTE_ADDR}."] [FATAL] $text\n";
		#print STDERR "(PID $$) [".$ENV{REMOTE_ADDR}."] [FATAL] $text\n";
		
		print "Content-Type: text/html\n\n";
		print "<style>pre {white-space: pre-wrap;white-space: -moz-pre-wrap;  white-space: -pre-wrap;      white-space: -o-pre-wrap;word-wrap: break-word;}</style><h1>Internal Server Error</h1>An error was encountered while processing the page you requested:<blockquote class='ffjc-error' style='margin-top:1.5em;margin-bottom:1.5em'><pre style='font-size:175%;font-weight:bold;margin-top:2px;margin-bottom:0'>$text</pre><br><a href='javascript:window.history.go(-1)'>&laquo; Return to the previous page ...</a><br><br></blockquote><p>For more information about this error, or help resolving this issue in a timely manner, please contact the webmaster at <a href='mailto:$AppCore::Config::WEBMASTER_EMAIL'>$AppCore::Config::WEBMASTER_EMAIL</a>.</p>";
		exit;
		
		
		
	}
	sub process
	{
		my $self = shift;
		
		my $q = shift;
		
		my $time_start = time;
		
		AppCore::Common->context->_reset;
	# 	AppCore::Session->_reset;
	# # 	
		AppCore::Common->context->{mod_fastcgi} = 1;
		
		$SIG{__WARN__} = sub 
		{
			my $user = AppCore::Common->context->user;
			print STDERR "(PID $$) [".($user ? $user->user."@" : "").$ENV{REMOTE_ADDR}."] [WARN] ".join(' ',@_)."\n";
		};
		
		$SIG{__DIE__} = sub 
		{
			my $err = join(" ", @_);
			return if $err =~ /(can't locate|undefined sub|Server returned error: Not permitted for method)/i;
			print STDERR AppCore::Common::print_stack_trace();
			
			my $user = AppCore::Common->context->user;
	# 		
			#send_email('josiahbryan@gmail.com','[AppCore Error] '.get_full_url(),"$err\n----------------------------------\n".AppCore::Common::get_stack_trace()."\n----------------------------------\nURL:  ".get_full_url()."\nUser: ".($user ? $user->display : "(no user logged in)\n"),1,$user ? eval '$user->email' || "noemail-empid-$user\@noemail.error" : 'notloggedin@nouser.error' );
	# 		
	# 		AppCore::Session->save();
			
			error("Internal Server Error",$err);
			#exit;
		};
		
		$ENV{REMOTE_ADDR} = $ENV{'HTTP_X_FORWARDED_FOR'} if defined $ENV{'HTTP_X_FORWARDED_FOR'};
		
		#print STDERR "($$) $ENV{REMOTE_ADDR}: ".get_full_url()."\n";
		
		my $is_mobile = 0;
		# If user specifies mobile pref in query, set cookie and flag
		if($ENV{QUERY_STRING} =~ /sitepref=(mobile|full)/)
		{
			setcookie('mobile.sitepref',$1);
			$is_mobile = $1 eq 'mobile';
		}
		else
		{
			# No explicit mobile pref specified, check cookie
			my $pref = getcookie('mobile.sitepref');
			#print STDERR "ism: $ism, ua: $ENV{HTTP_USER_AGENT}\n";
			
			# No cookie, check if is mobile based on UA
			if(!$pref && ismobile($ENV{HTTP_USER_AGENT}))
			{
				setcookie('mobile.sitepref','mobile');
				$is_mobile = 1;
			}
			else
			{
			# Got cookie, set flag based on pref
				$is_mobile = $pref eq 'mobile';
			}
		}
		
		# Store mobile flag for other modules to use so they dont have to check cookie
		AppCore::Common->context->mobile_flag($is_mobile);
		
		# Reset current theme incase it gets changed
		Content::Page::Controller->theme($AppCore::Config::THEME_MODULE);
		
		# Mudge path info and extract the request app name from the path
		my $path = $ENV{PATH_INFO};
		
		# Give current theme a chance to remap the URL before ANY processing is done on it
		if(my $new_url = Content::Page::Controller->theme->remap_url($path))
		{
			$path = $ENV{PATH_INFO} = $new_url;
		}
		
		# Strip first slash from URL since not relevant
		$path =~ s/^\///g;
		
		# Redirect frontpage to a dedicated mobile landing
		if($AppCore::Config::MOBILE_REDIR &&
		   $AppCore::Config::MOBILE_URL   &&
		   $is_mobile &&
		  !$path)
		{
			AppCore::Web::Common->redirect($AppCore::Config::MOBILE_URL);
		}
		
		# httpd.conf's rewrite rules should not have sent us this request if the file existed,
		# so we assume here that it doesn't exist in htdocs root and do our logic accordingly.
		if($path eq 'favicon.ico' &&
		   $AppCore::Config::USE_THEME_FAVICON)
		{
			# If $USE_THEME_FAVICON is any other value than 1, assume its a filename
			my $file = $AppCore::Config::USE_THEME_FAVICON ne '1' ?
			           $AppCore::Config::USE_THEME_FAVICON : $path;
			
			# Tell the webserver to redirect - that way, we allow the server to check for not-modified (and return status 304), etc
			AppCore::Web::Common->redirect(join('/', $AppCore::Config::WWW_ROOT, 'modules', $AppCore::Config::THEME_MODULE, $file),{expire_days=>31});
		}
		
		my $orig_path = $path;
		
		$path = $AppCore::Config::DEFAULT_MODULE if !$path;
		
		my $app = $path;
		$app =~ s/^(.*?)(?:\/(.*))$/$1/;
		$path = $2;
		
 		my $mod_ref = $self->{module_cache}->{lc $app}; #->{module};
		
		if(!$mod_ref)
		{
			# Content is the generic content tree module
			$mod_ref = $self->{module_cache}->{content};
		}
		
		#my $mod_ref = AppCore::Web::Module::bootstrap($mod_pkg);
		my $mod_obj = $mod_ref->{obj};
		
		#print $mod_obj->main();
		
		# Compose the arguments hashref for the app
		#my $q = new CGI;
		my $args = $q->Vars; #$q->Vars;
		$args->{PATH_INFO} = $path;
		
		my $ctx_ref;
		$ctx_ref = AppCore::Common->context();
		$ctx_ref->current_module($app);
		$ctx_ref->http_args($args);
		$ctx_ref->http_root(''); #$root);
		$ctx_ref->http_bin('');#$env);
		$ctx_ref->x('IsMobile',ismobile( $ENV{HTTP_USER_AGENT} ));
		
		REPROCESS_AUTHENTICATION:
		eval
		{
			authenticate();
		};
		if($@ =~ /MySQL server has gone away/)
		{
			AppCore::DBI->clear_handle_cache;
			goto REPROCESS_AUTHENTICATION;
		}
		
		my $url = get_full_url;
		#print STDERR "(PID $$) [".($ctx_ref->user ? $ctx_ref->user->user.'@' : '' ).$ENV{REMOTE_ADDR}."] $url\n" unless $url =~ /(res\/|forms\/validate)/;
		print STDERR "[".($ctx_ref->user ? $ctx_ref->user->user.'@' : '' ).$ENV{REMOTE_ADDR}."] $url\n" unless $url =~ /(res\/|forms\/validate)/;
		# || $ENV{REMOTE_ADDR} eq '10.0.1.60'; # netmon ip
		
		my $request = AppCore::Web::Request->new($args);
		$request->push_page_path($app);
		
		$ctx_ref->current_request($request);
		
		$app = 'Content' if !$app;
		
		REPROCESS_ON_SERVER_GONE:
		
		eval
		{
			# Do the actual processing. 
			# Normally, process_request is handled in AppCore::Module::WebApp, which intercepts
			# any 'res/' paths in PATH_INFO, then process_request calls handle_request,
			# which should be overridden in child classes. However, child classes
			# can choose to handle process_request themselves and do whatever they want
			# with 'res/' paths.
			
			my $response = $mod_obj->dispatch($request, AppCore::Web::Result->new);
			
			#die Dumper $response;
			
			binmode STDOUT;
			
			# Process output HTTP codes
			my $code = $response->status;
			#print STDERR "$path: $code: $out[0] (".length($out[1])." bytes) (".substr($out[1],0,5).")\n";
			if($code == 200)
			{
				#print "Content-Type: $out[0]\r\n\r\n";
				my $ctype = $response->content_type;
				my $data = $response->body;
				#my %args = @out;
				
				print "Content-Type: $ctype\r\n";
				#print "$_: $args{$_}\r\n" foreach keys %args;
				print "\r\n";
				print $data;
			#	print "<hr><i>Process Hit # ".AppCore::Common->context->{mod_fastcgi}."</i>";
			}
			elsif($code == 302)
			{
				print "Status: 302 Moved Temporarily\r\nLocation: ".$response->body."\r\n\r\n";
			}
			elsif($code == 404)
			{
				#$out[0]||='text/html';
				print "Status: 404 File Not Found\r\n";
				print "Content-Type: ".($response->content_type || 'text/html')."\r\n\r\n";
				print $response->body || "<h1>404 File Not Found</h1>Sorry, the requested URL does not exist.";
			}
			elsif($code == 500)
			{
				print "Status: 500 Internal Server Error\r\n";
				print "Content-Type: ".$response->content_type."\r\n\r\n";
				print $response->body;
			}
			elsif($code)
			{
				error("Unknown Code $code","Unknown Code $code from app $app");
			}
		};
		
		if($@)
		{
			my $err = $@;
			
			if($err =~ /MySQL server has gone away/)
			{
				AppCore::DBI->clear_handle_cache;
				goto REPROCESS_ON_SERVER_GONE;
			}
			else
			{	
				my $user = AppCore::Common->context->user;
				
				
				#send_email($AppCore::Config::WEBMASTER_EMAIL,'[AppCore Error] '.get_full_url(),"$err\n----------------------------------\n".AppCore::Common::get_stack_trace()."\n----------------------------------\nURL:  ".get_full_url()."\nUser: ".($user ? $user->display : "(no user logged in)\n"),1,$user ? eval '$user->compref->email' || "noemail-empid-$user\@noemail.error" : 'notloggedin@nouser.error' );
				
				#AppCore::Session->save();
				error("Internal Server Error",$err);
			}
		}
		
		END_HTTP_REQUEST:
		
		my $time_end = time;
		my $diff = $time_end - $time_start;
		my $show_time = 1;
		#my $show_time = $ENV{QUERY_STRING} =~ /dispatch_time_debug/;
		print STDERR "$url: [Duration: ".int($diff * 1000) . " ms]\n" if $url && $show_time; 
		#################
	}


	sub in_array {
		my ($arr,$search_for) = @_;
		my %items = map {$_ => 1} @$arr; # create a hash out of the array values
		return (exists($items{$search_for}))?1:0;
	}
	
	sub ismobile {
		my $useragent=lc(shift());
		my $is_mobile = '0';
	
		if($useragent =~ m/(android|up.browser|up.link|mmp|symbian|smartphone|midp|wap|phone)/i) {
			$is_mobile=1;
		}
		#print STDERR "ismobile: ua: '$useragent'\n";
	
		if((index($ENV{HTTP_ACCEPT},'application/vnd.wap.xhtml+xml')>0) || ($ENV{HTTP_X_WAP_PROFILE} || $ENV{HTTP_PROFILE})) {
			$is_mobile=1;
		}
	
		my $mobile_ua = lc(substr $ENV{HTTP_USER_AGENT},0,4);
		my @mobile_agents = ('w3c ','acs-','alav','alca','amoi','andr','audi','avan','benq','bird','blac','blaz','brew','cell','cldc','cmd-','dang','doco','eric','hipt','inno','ipaq','java','jigs','kddi','keji','leno','lg-c','lg-d','lg-g','lge-','maui','maxo','midp','mits','mmef','mobi','mot-','moto','mwbp','nec-','newt','noki','oper','palm','pana','pant','phil','play','port','prox','qwap','sage','sams','sany','sch-','sec-','send','seri','sgh-','shar','sie-','siem','smal','smar','sony','sph-','symb','t-mo','teli','tim-','tosh','tsm-','upg1','upsi','vk-v','voda','wap-','wapa','wapi','wapp','wapr','webc','winw','winw','xda','xda-');
	
		if(in_array(\@mobile_agents,$mobile_ua)) {
			$is_mobile=1;
		}
	
		if ($ENV{ALL_HTTP}) {
			if (index(lc($ENV{ALL_HTTP}),'OperaMini')>0) {
				$is_mobile=1;
			}
		}
	
		if (index(lc($ENV{HTTP_USER_AGENT}),'windows')>0) {
			$is_mobile=0;
		}
	return $is_mobile;
	}
	
	sub isiphone {
	
		my $useragent = @_;
		my $iphone=0;
		if (lc($useragent) =~ m/iphone/) {
			$iphone=1;
		}
		return $iphone;
	}
	
	sub isipad {
	
		my $useragent = @_;
		my $ipad=0;
		if (lc($useragent) =~ m/ipad/) {
			$ipad=1;
		}
		return $ipad;
	}

};
1;