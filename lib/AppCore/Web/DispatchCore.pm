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
	use AppCore::Web::MobileDetect;
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
		print STDERR "(PID $$) [".($ctx_ref->user ? $ctx_ref->user->user."@" : "").$ENV{REMOTE_ADDR}."] [FATAL] $text (url: ".get_full_url().")\n";
		#print STDERR "(PID $$) [".$ENV{REMOTE_ADDR}."] [FATAL] $text\n";
		
		my $email = AppCore::Config->get('WEBMASTER_EMAIL');
		#print STDERR "Webmaster email: '$email'\n";
		
		print "Content-Type: text/html\n\n";
		print "<style>pre {white-space: pre-wrap;white-space: -moz-pre-wrap;  white-space: -pre-wrap;      white-space: -o-pre-wrap;word-wrap: break-word;}</style><h1>Internal Server Error</h1>An error was encountered while processing the page you requested:<blockquote class='ffjc-error' style='margin-top:1.5em;margin-bottom:1.5em'><pre style='font-size:175%;font-weight:bold;margin-top:2px;margin-bottom:0'>$text</pre><br><a href='javascript:window.history.go(-1)'>&laquo; Return to the previous page ...</a><br><br></blockquote><p>For more information about this error, or help resolving this issue in a timely manner, please contact the webmaster at <a href='mailto:${email}'>${email}</a>.</p>";
		exit;
		
		
		
	}
	
	our $DISPATCH_START_TIME;
	
	sub setup_request
	{
		my ($self, $q) = @_;
		
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
			print STDERR "Error: $err, Stack trace:\n";
			AppCore::Common::print_stack_trace();
			
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
		Content::Page::Controller->theme(AppCore::Config->get("THEME_MODULE"));
		
		# Mudge path info and extract the request app name from the path
		my $path = $ENV{PATH_INFO};
		
		# Give current theme a chance to remap the URL before ANY processing is done on it
		my $theme = Content::Page::Controller->theme;
		eval 
		{
			if(my $new_url = $theme->remap_url($path))
			{
				$path = $ENV{PATH_INFO} = $new_url;
			}
		};
		if($@ =~ /" via package "$theme"/)
		{
			$Content::Page::Controller::CurrentTheme = 'Content::Page::ThemeEngine';
			$AppCore::Config::THEME_MODULE = 'ThemeBasic';
			#warn "Error loading config theme $theme, resorting to internal theme '$Content::Page::Controller::CurrentTheme'";
			warn "Error loading config theme $theme, resorting to internal theme '$Content::Page::Controller::CurrentTheme', module '$AppCore::Config::THEME_MODULE'";
		}
		elsif($@)
		{
			warn "Warn: $@";
		}
		
		# Strip first slash from URL since not relevant
		$path =~ s/^\///g;
		
		# Redirect frontpage to a dedicated mobile landing
		if(AppCore::Config->get("MOBILE_REDIR") &&
		   AppCore::Config->get("MOBILE_URL")   &&
		   $is_mobile &&
		  !$path)
		{
			AppCore::Web::Common->redirect(AppCore::Config->get("MOBILE_URL"));
		}
		
		# httpd.conf's rewrite rules should not have sent us this request if the file existed,
		# so we assume here that it doesn't exist in htdocs root and do our logic accordingly.
		if($path eq 'favicon.ico' &&
		   AppCore::Config->get("USE_THEME_FAVICON"))
		{
			# If $USE_THEME_FAVICON is any other value than 1, assume its a filename
			my $file = AppCore::Config->get("USE_THEME_FAVICON") ne '1' ?
			           AppCore::Config->get("USE_THEME_FAVICON") : $path;
			
			# Tell the webserver to redirect - that way, we allow the server to check for not-modified (and return status 304), etc
			AppCore::Web::Common->redirect(join('/', AppCore::Config->get("WWW_ROOT"), 'modules', AppCore::Config->get("THEME_MODULE"), $file),{expire_days=>31});
		}
		
		if($path eq 'iepngfix.htc')
		{
			return $self->send_iepngfix();
		}
		
		my $orig_path = $path;
		
		$path = AppCore::Config->get("DEFAULT_MODULE") if !$path;
		
		my $app = $path;
		$app =~ s/^(.*?)(?:\/(.*))$/$1/;
		$path = $2;
		
 		my $mod_ref;
 		if($app)
 		{
 			$mod_ref = $self->{module_cache}->{lc $app}; #->{module};
 		}
		
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
		#print STDERR "[".($ctx_ref->user ? $ctx_ref->user->user.'@' : '' ).$ENV{REMOTE_ADDR}."] $ENV{HTTP_HOST}${url}\n" unless $url =~ /poll/ || $ENV{HTTP_USER_AGENT} =~ /Googlebot/;
		print STDERR "[".($ctx_ref->user ? $ctx_ref->user->user.'@' : '' ).$ENV{REMOTE_ADDR}."] ${url}\n" unless $url =~ /poll/ || $ENV{HTTP_USER_AGENT} =~ /bot/;
		# || $ENV{REMOTE_ADDR} eq '10.0.1.60'; # netmon ip
		
		# Reset modpath and binpath caches on each request
		%AppCore::Web::Module::ModpathCache = ();
		%AppCore::Web::Module::BinpathCache = ();
		
		my $request = AppCore::Web::Request->new($args);
		$request->push_page_path($app);
		
		$ctx_ref->current_request($request);
		
		#$app = 'Content' if !$app;
		
		return ($mod_obj, $request, $url);
	}
	
	sub process
	{
		my $self = shift;
		
		my $q = shift;
		
		my $just_response = shift || 0;
		
		my $time_start = $DISPATCH_START_TIME = time;
		
		my ($mod_obj, $request, $url) = $self->setup_request($q);
		
		my $response = $self->execute_request($mod_obj, $request, $just_response);
		
		END_HTTP_REQUEST:
		
		my $time_end = time;
		my $diff = $time_end - $time_start;
		my $show_time = $ENV{QUERY_STRING} =~ /dispatch_time_debug/ || $ENV{HTTP_REFERER} =~ /dispatch_time_debug/;
		#my $show_time = 1;
		print STDERR "$url: [Duration: ".int($diff * 1000) . " ms]\n" if $url && $show_time && $url !~ /poll/;
		#################
		
		return $response;
	}
	
	sub execute_request
	{
		my $self = shift;
		my ($mod_obj, $request, $just_response) = @_;
		
		my $output_res = undef;
		
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
			
			$output_res = $response;
			
			if(!$just_response)
			{
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
					error("Unknown Code $code","Unknown Code $code from $mod_obj");
				}
			}
		};
		
		if($@)
		{
			my $err = $@;
			
			if($err =~ /MySQL server has gone away/)
			{
				AppCore::DBI->clear_handle_cache;
				AppCore::DBI->setup_modtime_sth;
				AppCore::DBI->clear_cached_dbobjects;
				goto REPROCESS_ON_SERVER_GONE;
			}
			else
			{	
				my $user = AppCore::Common->context->user;
				
				
				#send_email(AppCore::Config->get("WEBMASTER_EMAIL"),'[AppCore Error] '.get_full_url(),"$err\n----------------------------------\n".AppCore::Common::get_stack_trace()."\n----------------------------------\nURL:  ".get_full_url()."\nUser: ".($user ? $user->display : "(no user logged in)\n"),1,$user ? eval '$user->compref->email' || "noemail-empid-$user\@noemail.error" : 'notloggedin@nouser.error' );
				
				#AppCore::Session->save();
				error("Internal Server Error",$err);
			}
		}
		
		return $output_res;
	}
	
	sub send_iepngfix
	{
		my $fix_file = 'ie/iepngfix/iepngfix.htc';
		
		print "Content-Type: text/x-component\r\n";
		print "\r\n";
		print AppCore::Common->read_file($fix_file);
	}

};
1;
