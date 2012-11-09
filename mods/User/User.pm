use strict;

package User::ActionHook;
{
	
	# User::ActionHook::EVT_NEW_FB_USER: {user=>$user_obj}
	# Calls when the user signs in with facebook for the first time
	sub EVT_NEW_FB_USER { 'EVT_NEW_FB_USER' }
	
	# User::ActionHook::EVT_NEW_USER: {user=>$user_obj}
	# Called when the user completes the signup process
	sub EVT_NEW_USER { 'EVT_NEW_USER' }
	
	# User::ActionHook::EVT_USER_ACTIVATED: {user=>$user_obj}
	# Called when a user (with no password) chooses a password, "activating" their account
	# This may be called if the user authenticates with facebook even if they don't choose a local password.
	sub EVT_USER_ACTIVATED { 'EVT_USER_ACTIVATED' }
	
	# User::ActionHook::EVT_USER_LOGIN: {user=>$user_obj}
	# This is only called during the actual login procedure in the 'User' module - e.g. not during the
	# AppCore::AuthUtil routines. It is called both on local login and FB authentication - both for
	# existing users AND new users
	sub EVT_USER_LOGIN { 'EVT_USER_LOGIN' }
	
	# User::ActionHook::EVT_USER_LOGOUT: {user=>$user_obj}
	# This is only called during an explicit 'logout' - e.g. it's NOT called if the user
	# just leaves the website.
	sub EVT_USER_LOGOUT { 'EVT_USER_LOGOUT' }
	
	# User::ActionHook::EVT_USER_ADDED_TO_GROUP: {user=>$user_obj,group=>$group}
	# This is called when the user is added to a new group
	# The 'group' argument is an AppCore::User::Group object.
	sub EVT_USER_ADDED_TO_GROUP { 'EVT_USER_ADDED_TO_GROUP' }
	
	# Any event
	sub EVT_ANY { 'EVT_ANY' }
	
	use base 'AppCore::DBI';
	__PACKAGE__->meta(
	{
		table	=> AppCore::Config->get("USER_ACTIONHOOK_DBTABLE") || 'user_actionhooks',
		
		schema	=> 
		[
			{ field => 'hookid',		type	=> 'int', @AppCore::DBI::PriKeyAttrs },
			{ field	=> 'event',		type	=> 'varchar(255)' },
			{ field	=> 'controller',	type	=> 'varchar(255)' },
			{ field	=> 'is_enabled',	type	=> 'int(1)', null=>0, default => 1 },
		],	
	});
	
	our %PacakgeCodeRefs;
	
	sub register
	{
		my $filter_ref = undef;
		undef $@;
		eval
		{
			my $pkg = shift;
			$pkg = ref $pkg if ref $pkg;
			
			my $event = shift;
			
			my $code_ref = shift || undef;
			
			$filter_ref = $pkg->find_or_create({controller=>$pkg, event=>$event});
			
			push @{ $PacakgeCodeRefs{$pkg} }, $code_ref if $code_ref;
			
		};
		warn $@ if $@;
		
		return $filter_ref;
	}
	
	sub hook
	{
		my $self = shift;
		my $event = shift;
		my $args = shift;
		
		my $pkg = ref $self ? ref $self : $self;
		
		# Default impl of hook() calls any code refs for this package
		my $code_ref_list = $PacakgeCodeRefs{$pkg};
		if($code_ref_list)
		{
			my @list = @{$code_ref_list || []};
			foreach my $code_ref (@list)
			{
				&{$code_ref}($event,$args);
			}
		}
		
		return 1;
	}
}

package User;
{
	use AppCore::Common;
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	# Use this to access Content::Page::Controller
	use Content::Page;
	
	# Our user storage object
	use AppCore::User;
	
	# For immediate transmission of the user's forgotten password email
	use AppCore::EmailQueue;
	
	# Register our admin component with the Admin module
	use Admin::ModuleAdminEntry;
	Admin::ModuleAdminEntry->register(__PACKAGE__, 'Users', 'users', 'Show registered users and associated profile data.');
	
	# Used in Facebook integration
	use LWP::Simple;
	use JSON::XS;
	
	sub new { bless {}, shift }
	
	my $SETTINGS_ACTION  = 'settings';
	my $LOGIN_ACTION  = 'login';
	my $SIGNUP_ACTION = 'signup';
	my $FORGOT_ACTION = 'forgot_pass';
	
	__PACKAGE__->WebMethods(qw/ 
		main
		settings
		login
		signup
		forgot_pass
	/);
	
	sub apply_mysql_schema
	{
		AppCore::User->apply_mysql_schema;
		User::ActionHook->mysql_schema_update;
	}
	
	sub main
	{
		my ($self,$req) = shift;
		
		my $url = AppCore::Common->context->user ? $SETTINGS_ACTION : $LOGIN_ACTION;
		
		AppCore::Web::Common->redirect($self->module_url($url));
	}
	
	sub get_facebook_redir_url
	{
		return shift->module_url('login/facebook', 1); # 1 = incl server
	}
	
	sub _set_if
	{
		my $obj = shift;
		my $key = shift;
		my $val = shift;
		$obj->set($key,$val) if $obj->get($key) ne $val;
	}
	
	sub run_hooks
	{
		my $self = shift;
		my $event = shift;
		my $args = shift;
		
		if($args)
		{
			$args->{event} = $event if !$args->{event};
		}
		else
		{
			$args = { event => $event };
		}
		
		my @hooks = User::ActionHook->search(event => $event);
		foreach my $hook (@hooks)
		{
			my $ctrl = $hook->controller;
			my $event_name = $event eq User::ActionHook::EVT_ANY() ? $args->{event} : $event;
			undef $@;
			eval $ctrl.'->hook($event_name,$args);';
			#$hook->hook($event, $args);
			warn "Problem running user action hook '$ctrl' for event '$event': ".$@ if $@;
		}
		
		$self->run_hooks(User::ActionHook::EVT_ANY, $args) if $event ne User::ActionHook::EVT_ANY;
		
		### HACK!!!!
		# Because of pacakage loading order, we have to put this code HERE. 
		# I'd rather have it as a PROPER hook in Content::Page, but due to the
		# order thigns are loaded, it wont let the a package in Content::Page
		# use 'User' as a parent class.
		if($event eq User::ActionHook::EVT_USER_LOGIN ||
		   $event eq User::ActionHook::EVT_USER_LOGOUT ||
		   $event eq User::ActionHook::EVT_USER_ADDED_TO_GROUP)
		{
			print STDERR __PACKAGE__.": User event: '$event', clearing nav cache\n";
			Content::Page::ThemeEngine->clear_nav_cache();
		}
	}
	
	sub connect_with_facebook
	{
		my ($self, $req, $r) = @_;
		
		if($req->{code})
		{
			# We're at step 1 - They've accepted us, now we have to get the access_token
			
			my $code = $req->code;
				
			my $token_url = 'https://graph.facebook.com/oauth/access_token?'
				. 'client_id='     . AppCore::Config->get("FB_APP_ID")
				.'&redirect_uri='  . $self->get_facebook_redir_url()
				.'&client_secret=' . AppCore::Config->get("FB_APP_SECRET")
				.'&code=' . $code;
			
			print STDERR "Authenticated FB code $code, now requesting access_token from $token_url\n";
			
			my $response = LWP::Simple::get($token_url);
			
			my ($token) = $response =~ /access_token=(.*)$/;
			
			my $expires = '0000-00-00 00:00:00';
			if($token =~ /&expires=(\d+)$/)
			{
				$expires = $1;
				$token =~ s/&expires=\d+//g;
				
				my $dt = DateTime->now(); #timezone => 'America/Chicago');
				$dt->add( seconds => $expires );
				
				$expires = $dt->datetime;
			}
			
			if($token)
			{
				my $user_url = 'https://graph.facebook.com/me?access_token='.$token;
				print STDERR "User URL: $user_url\n";
				my $user_json = LWP::Simple::get($user_url);
				if($user_json =~ /email/)
				{
					my $user_data = decode_json($user_json);
					
					my $email = $user_data->{email};
					$email =~ s/\\u0040/@/g;
					
					my $display = $user_data->{name};
					my $first   = $user_data->{first_name};
					my $last    = $user_data->{last_name};
					my $phone   = $user_data->{phone};
					my $local   = $user_data->{location}->{name};
					my $tz_off  = $user_data->{timezone};
					my $fb_user = $user_data->{username};
					my $fb_userid = $user_data->{id};
					
					my $user_obj = AppCore::User->by_field(email => $email);
					$user_obj = AppCore::User->by_field(display => $display) if !$user_obj;
					$user_obj = AppCore::User->by_field(display => $first." ".$last) if !$user_obj;
					
					my $new_user = 0;
					if(!$user_obj)
					{
						$user_obj = AppCore::User->insert({ user => $fb_user });
						$new_user = 1;
						print STDERR "Created new user from facebook data: $display - $email, userid $user_obj\n"; 
					}
					else
					{
						print STDERR "Matched facebook user to existing user: $display - $email, userid $user_obj\n";
					}
					
					
					$user_obj->user($fb_user)    if ($user_obj->user =~ /\@/ && $user_obj->user ne $email) || !$user_obj->user;
					$user_obj->email($email)     if $user_obj->email    ne $email;
					$user_obj->first($first)     if $user_obj->first    ne $first;
					$user_obj->last($last)       if $user_obj->last     ne $last;
					$user_obj->display($display) if $user_obj->display  ne $display;
					$user_obj->phone($phone)     if $user_obj->phone    ne $phone;
					$user_obj->location($local)  if $user_obj->location ne $local;
					$user_obj->tz_off($tz_off)   if $user_obj->tz_off   ne $tz_off;
					$user_obj->fb_user($fb_user) if $user_obj->fb_user  ne $fb_user;
					$user_obj->fb_userid($fb_userid) if $user_obj->fb_userid ne $fb_userid;
					
					_set_if($user_obj, $_, $user_data->{location}->{$_}) foreach qw/street city state country zip latitude longitude/;
					
					$user_obj->get_fb_photo();
					
					# If the user record existed prior to this interaction, but no password assigned,
					# and the 'is_fbuser' is false, and it's not a $new_user, then the user has
					# in a sense 'activated' their local account via facebook.
					if(!$new_user && 
					    $user_obj->is_fbuser && 
					   !$user_obj->pass)
					{
						$self->run_hooks(User::ActionHook::EVT_USER_ACTIVATED,{user=>$user_obj});
					}
					
					if(!$user_obj->pass)
					{
						$user_obj->pass($token);
					}
					
					$user_obj->is_fbuser(1);
					$user_obj->fb_token($token);
					$user_obj->fb_token_expires($expires);
					$user_obj->update;
					
					if($new_user)
					{
						$self->run_hooks(User::ActionHook::EVT_NEW_FB_USER,{user=>$user_obj});
					}
					
					#if(AppCore::AuthUtil->authenticate($user_obj->user, $token))
					if(AppCore::AuthUtil->authenticate($user_obj->user, $user_obj->pass))
					{
						$self->run_hooks(User::ActionHook::EVT_USER_LOGIN,{user=>$user_obj});
						
						my $url_from = AppCore::Web::Common->url_decode(getcookie('login.url_from')); # in case they use FB to login....
						$url_from = AppCore::Config->get('WELCOME_URL') if !$url_from  || $url_from =~ /\/(login|logout)/;
						print STDERR "Authenticated ".AppCore::Common->context->user->display." with facebook token $token, redirecting to $url_from\n";
						return $r->redirect($url_from);
					}
					else  # Can't authenticate  
					{
						eval{ print STDERR "Failure info: userid $user_obj, username:".$user_obj->user.", token:$token, pass:".$user_obj->pass."\n"; }; undef $@;
						return $r->error("Facebook API Error","Unable to connect facebook data to local account.");
					}
				}
				else # can't find email in data from FB
				{
					# Error getting user data, show error msg
					return $r->error("Facebook API Error","Problem getting user data:<br><code>$user_json</code>");
				}
			}
			else
			{
				# Error getting token, show error msg
				return $r->error("Facebook API Error","Problem getting access token - make sure \$FB_APP_ID and \$FB_APP_SECRET are correct in appcore/conf/appcore.conf.<br><code>$response</code>");
			}
		}
		else
		{
			# Error getting code, show error msg
			return $r->redirect( $self->module_url("login") );
		}
	}
	
	sub login
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $action = $req->next_path || '';
		
		#print STDERR "auth($action): ".Dumper($req);
			
		if($action eq 'facebook')
		{
			return $self->connect_with_facebook($req,$r);
		}
		
		if($action eq 'authenticate' && AppCore::AuthUtil->authenticate($req->{user},$req->{pass})) #,1))
		{
			$self->run_hooks(User::ActionHook::EVT_USER_LOGIN,{user=>AppCore::Common->context->user});
			
			my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
			$url_from = AppCore::Config->get("WELCOME_URL") if !$url_from  || $url_from =~ /\/(login|logout)/;
			print STDERR "Authenticated ".AppCore::Common->context->user->display.", redirecting to $url_from\n";
			setcookie('login.url_from',''); # delete cookie
			return $r->redirect($url_from);
		}
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		# Fell thru from auth attempt, so check to see if it has a user but no password
		if($action eq 'authenticate')
		{
			#print STDERR "auth fall thru: mark1\n";
			my $user = AppCore::User->by_field(user=>$req->{user});
			$user = AppCore::User->by_field(email=>$req->{user}) if !$user;
			if($user && !$user->pass)
			{
				my $url = $self->module_url($SIGNUP_ACTION) . '?user='.AppCore::Web::Common->url_encode($user->user);
				print STDERR "auth fall thru: mark2: $url\n";
				return $r->redirect($url);
			}
			#print STDERR "auth fall thru: mark3\n";
		}
			
		
		if(AppCore::Common->context->user)
		{
			$self->run_hooks(User::ActionHook::EVT_USER_LOGOUT,{user=>AppCore::Common->context->user});
			
			AppCore::AuthUtil->logoff;
			
			print STDERR "auth logoff\n";
			
			# Redirect back here inorder for any user-dependent template features to adjust given the logout
			return $r->redirect($self->module_url($LOGIN_ACTION) . '?url_from='.$url_from.'&was_loggedin=1');
		}
		
		print STDERR "auth tmpl output\n";	
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('login'.($mobile?'-mobile' : '').'.tmpl');
		#$tmpl->param(challenge => AppCore::AuthUtil->get_challenge());
		setcookie('login.url_from',$url_from); # in case they use FB to login....
		
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		$tmpl->param(was_loggedin => $req->{was_loggedin});
		$tmpl->param(sent_pass    => $req->{sent_pass});
		$tmpl->param(fb_app_id	  => AppCore::Config->get("FB_APP_ID"));
		$tmpl->param(fb_redir_url => $self->get_facebook_redir_url());
		#$tmpl->param(auth_requested => $req->{auth_requested});
		# Shouldn't get here if login was ok (redirect above), but since we're here with the authenticate page, assume they failed login
		$tmpl->param(bad_login => 1) if $action eq 'authenticate';
		
		$tmpl->param(fb_permissions_list => AppCore::Config->get('FB_EXTRA_PERMS'));
		
		$view->breadcrumb_list->push('Home',"/",0);
		$view->breadcrumb_list->push('Login',"/user/login",0);
		$view->output($tmpl);
	
		
		
		return $r;
	}
	
	sub signup
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $sub_page = $req->next_path;
		
		#print STDERR "auth($sub_page): ".Dumper($req,$page);
			
		#print STDERR MY_LINE()."auth($sub_page): mark\n";


		if($sub_page eq 'post')
		{
			my $name = $req->{name};
			my $email = $req->{user};
			my $pass = $req->{pass};
			
			my $signup_ok = $self->signup_user($name, $email, $pass);
			
			if($signup_ok)
			{
				print STDERR MY_LINE()."auth($sub_page): mark: signup_ok\n";
				#my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
				#$url_from = AppCore::Common->context->http_bin.'/welcome' if !$url_from;
				my $url_from = AppCore::Config->get("WELCOME_URL");
				return $r->redirect($url_from);
			}
		}
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('signup.tmpl'); #'.($mobile?'-mobile' : '').'.tmpl');
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		
		my $user = AppCore::User->by_field(user=>$req->{user});
		if($user && !$user->pass)
		{
			$tmpl->param(name => $user->display);
		}
		
		# Shouldn't get here if signup was ok
		$tmpl->param(email_exists => 1) if $sub_page eq 'post';
		
		$view->breadcrumb_list->push('Home',"/",0);
		$view->breadcrumb_list->push('Signup',".",0);
		#$r->output($tmpl);
		$view->output($tmpl);
		
		return $r;
	}
	
	sub signup_user
	{
		my $self = shift;
		my ($name, $email, $pass) = @_;
		
		my $signup_ok = 0;
		
		my $user = AppCore::User->by_field(email => $email);
		   $user = AppCore::User->by_field(user  => $email) if !$user;

		my $name_short = AppCore::Config->get("WEBSITE_NAME");
		my $name_noun  = AppCore::Config->get("WEBSITE_NOUN");
		my @admin_emails = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
		
		if($user && !$user->pass)
		{
			print STDERR MY_LINE()."signup_user(): mark: case 1 ($user)\n";
			$signup_ok = 1;
			$user->pass($pass);
			$user->email($email);
			$user->user($email);
			$user->display($name) if $name;
			$user->update;
			
			AppCore::AuthUtils->authenticate($user,$pass);
			
			AppCore::Common->send_email(\@admin_emails,"[$name_short] User Activated: $email","User '$email', name '$name' has now activated their account.");
			AppCore::Common->send_email([$user->email],"[$name_short] Welcome to $name_noun!","You've successfully activated your $name_noun account!\n\n" . (AppCore::Config->get("WELCOME_URL") ? "Where to go from here:\n\n    ".join('/', AppCore::Config->get("WEBSITE_SERVER"), AppCore::Config->get("DISPATCHER_URL_PREFIX"), AppCore::Config->get("WELCOME_URL")):""));
			
			$self->run_hooks(User::ActionHook::EVT_USER_ACTIVATED,{user=>$user});
		}
		elsif(!$user)
		{
			print STDERR MY_LINE()."signup_user(): mark: case2\n";
			$signup_ok = 1;
			
			my $user_ref = AppCore::User->insert({user=>$email,email=>$email,display=>$name,pass=>$pass});
			AppCore::AuthUtil->authenticate($email,$pass);
			
			AppCore::Common->send_email(\@admin_emails,"[$name_short] New User: $email","New user '$email', name '$name' just signed up!");
			AppCore::Common->send_email([$user_ref->email],"[$name_short] Welcome to $name_noun!","You've successfully signed up for your own $name_noun account!\n\n" . (AppCore::Config->get("WELCOME_URL") ? "Where to go from here:\n\n    ".join('/', AppCore::Config->get("WEBSITE_SERVER"), AppCore::Config->get("DISPATCHER_URL_PREFIX"), AppCore::Config->get("WELCOME_URL")):""));
			
			$self->run_hooks(User::ActionHook::EVT_NEW_USER,{user=>$user_ref});

			$user = $user_ref;
		}

		if($signup_ok)
		{
			$self->run_hooks(User::ActionHook::EVT_USER_LOGIN,{user=>$user});
		}
		
		return $user;
	}


	sub forgot_pass
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $sub_page = $req->next_path;
		
		#print STDERR "auth($sub_page): ".Dumper($req,$page);
		my $name_short = AppCore::Config->get("WEBSITE_NAME");
		my $name_noun  = AppCore::Config->get("WEBSITE_NOUN");
		my @admin_emails = @{ AppCore::Config->get('ADMIN_EMAILS') || [] };
		
		if($sub_page eq 'post')
		{
			my $email = $req->{user};
			
			my $user = AppCore::User->by_field(email=>$email);
			if($user && $user->pass)
			{
				AppCore::Common->send_email(\@admin_emails,"[$name_short] User Forgot Password: $email","User '$email' forgot their password.\n\nCorrect password is:\n\n    ".$user->pass);
				
				my $url_from = $self->module_url($LOGIN_ACTION,1) . '?url_from='.$req->{url_from}.'&user='.AppCore::Web::Common->url_encode($email);
				
				my $msg_ref = AppCore::EmailQueue->send_email([$user->email],"[$name_short] Forgotten Password","You or someone using your email requested your password. Your password is:\n\n    ".$user->pass."\n\nYou may enter your password at:\n\n    $url_from\n\n");
				
				# Send right away so the user doesn't have to wait for the crontab daemon to run at the top of the minute
				$msg_ref->transmit;
				
				return $r->redirect($url_from.'&sent_pass=1');
			}
		}
		
		my $url_from = AppCore::Web::Common->url_encode(
					AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('forgot_pass.tmpl'); #'.($mobile?'-mobile' : '').'.tmpl');
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		
		# Shouldn't get here if signup was ok
		$tmpl->param(invalid_email => 1) if $sub_page eq 'post';
		
		$view->breadcrumb_list->push('Home',"/",0);
		$view->breadcrumb_list->push('Login',"/user/login",0);
		$view->breadcrumb_list->push('Forgot Pass',".",0);
		$view->output($tmpl);
		
		return $r;
	}
	
	sub settings
	{
		my ($self,$req,$r) = @_;
		
		my $sub_page = $req->next_path;
		
		# User must be logged in to change settings
		AppCore::AuthUtil->require_auth;
		
		my $user = AppCore::Common->context->user;
		
		
		if($sub_page eq 'advanced')
		{
			my $for_user = $req->{userid};
			if($for_user)
			{
				if($for_user != $user->id && !$user->check_acl(AppCore::Config->get("ADMIN_ACL")))
				{
					return $r->error("Not Administrator","Sorry, you must be an administrator to change the settings for another user other than you rown account.");
				}
				
				$user = AppCore::User->retrieve($for_user);
				
				return $r->error("Unknown UserID","Sorry, the userid you gave does not match any userid in the database.") if !$user;
			}
			print STDERR __PACKAGE__."->settings(): user:".$user->display."\n";
			
			
			$req->push_page_path($req->shift_path);
			
			my @all_options = AppCore::User::PrefOption->retrieve_from_sql('1 order by controller, module_name, subsection_name, optid');
			
			my $np = $req->next_path;
			if($np eq 'post')
			{
				foreach my $opt (@all_options)
				{	
					my $val = AppCore::User::Preference->find_or_create(optid => $opt, userid => $user);
					$val->value($req->{'opt_'.$opt->id});
					$val->update;
				}
			}
			
			my $last_values = undef;
			foreach my $opt (@all_options)
			{
				#$last_values = { mod => $opt->module_name, sec => $opt->subsection_name } if !$last_values;
				
				my $val = AppCore::User::Preference->by_field(optid => $opt, userid => $user);
				$opt->{$_} = $opt->get($_) foreach $opt->columns;
				$opt->{'type_'.$opt->datatype} = 1;
				$opt->{value} = $val ? $val->value : $opt->default_value;
				$opt->{mod_change} = 1 if $last_values->{mod} ne $opt->module_name;
				$opt->{sec_change} = 1 if $last_values->{sec} ne $opt->subsection_name;
				
				$last_values = { mod => $opt->module_name, sec => $opt->subsection_name };
			}
			
			
			return $r->redirect($req->url_from) if $np eq 'post' && $req->url_from;
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			
			my $mobile = getcookie('mobile.sitepref') eq 'mobile';
			
			my $tmpl = $self->get_template('advopts.tmpl'); #.($mobile?'-mobile' : '').'.tmpl');
			$tmpl->param('saved' => 1) if $np eq 'post';
			
			$tmpl->param(opts => \@all_options);
			$tmpl->param(url_from => $req->{url_from}) if $req->url_from;
			$tmpl->param('user_'.$_ => $user->get($_)) foreach $user->columns;
			$tmpl->param(for_user => $for_user);
			
			$view->breadcrumb_list->push('Home',"/",0);
			$view->breadcrumb_list->push('Settings',"/user/settings",0);
			$view->breadcrumb_list->push('Advanced',"/user/settings/advanced",0);
			#$r->output($tmpl);
			$view->output($tmpl);
			return $r;
		}
		else
		{
			
			if($sub_page eq 'post')
			{
				my $name = $req->{name};
				my $email = $req->{new_user_value};
				my $pass = $req->{new_pass_value};
				
				$user->pass($pass) if $pass && $pass !~ /^\*+$/;
				$user->email($email) if $email;
				$user->user($email) if $email;
				$user->display($name) if $name;
				if($user->is_changed)
				{
					$user->update;
					AppCore::AuthUtil->authenticate($user->user,$user->pass);
					
					## Re-apply 'user_' template variables, since they were applied in the load_template() call and won't see the updates we just saved
					##$skin->param('user_'.$_ => $user->get($_)) foreach $user->columns
				}
			}
			
			return $r->redirect($req->url_from) if $sub_page eq 'post' && $req->url_from;
			
			my $view = Content::Page::Controller->get_view('sub',$r);
			
			my $mobile = getcookie('mobile.sitepref') eq 'mobile';
			
			my $tmpl = $self->get_template('profile.tmpl'); #'.($mobile?'-mobile' : '').'.tmpl');
			$tmpl->param('user_'.$_ => $user->get($_)) foreach $user->columns;
			$tmpl->param('profile_saved' => 1) if $sub_page eq 'post';
			$tmpl->param(fake_pass => join '', ('*') x length($user->pass));
			$tmpl->param(url_from => $req->{url_from}) if $req->url_from;
			
			$view->breadcrumb_list->push('Home',"/",0);
			$view->breadcrumb_list->push('Settings',"/user/settings",0);
			#$r->output($tmpl);
			$view->output($tmpl);
			return $r;
		}
	}
	
	sub unsubscribe
	{
		my ($class,$skin,$r,$page,$req,$path) = @_;
		
		my $sub_page = shift @$path;
		
		AppCore::User::Auth->require_authentication;
			
	}
}