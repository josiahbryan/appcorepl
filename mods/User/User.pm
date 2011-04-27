use strict;
package User;
{
	use AppCore::Common;
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	# Use this to access Content::Page::Controller
	use Content::Page;
	
	# Our user storage object
	use AppCore::User;
	
	# Register our admin component with the Admin module
	use Admin::ModuleAdminEntry;
	Admin::ModuleAdminEntry->register(__PACKAGE__, 'Users', 'users', 'Show registered users and associated profile data.');
	
	# Used in Facebook integration
	use LWP::Simple;
	use JSON::XS;
	
	sub new { bless {}, shift }
	
	my $LOGIN_ACTION  = 'login';
	my $SIGNUP_ACTION = 'signup';
	my $FORGOT_ACTION = 'forgot_pass';
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		login
		signup
		forgot_pass
	/);
	
	sub apply_mysql_schema
	{
		AppCore::User->apply_mysql_schema;
	}
	
	sub main
	{
		my ($self,$req) = shift;
		
		AppCore::Web::Common->redirect($self->module_url($LOGIN_ACTION));
	}
	
	sub get_facebook_redir_url
	{
		return shift->module_url('login/facebook', 1); # 1 = incl server
	}
	
	sub connect_with_facebook
	{
		my ($self, $req, $r) = @_;
		
		if($req->{code})
		{
			# We're at step 1 - They've accepted us, now we have to get the access_token
			
			my $code = $req->code;
			print STDERR "Authenticated FB code $code, now requesting access_token\n";
				
			my $token_url = 'https://graph.facebook.com/oauth/access_token?'
				. 'client_id=192357267468389'
				.'&redirect_uri='  . $self->get_facebook_redir_url()
				.'&client_secret=' . $AppCore::Config::FB_APP_SECRET
				.'&code=' . $code;
			
			my $response = LWP::Simple::get($token_url);
			
			my ($token) = $response =~ /access_token=(.*)$/;
			
			my $expires = '0000-00-00 00:00:00';
			if($token =~ /&expires=(\d+)$/)
			{
				$expires = $1;
				$token =~ s/&expires=\d+//g;
				
				my $dt = DateTime->now(timezone => 'America/Chicago');
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
					my $fb_user = $user_data->{username};
					my $local   = $user_data->{location}->{name};
					my $tz_off  = $user_data->{timezone};
					
					my $user_obj = AppCore::User->by_field(email => $email);
					$user_obj = AppCore::User->by_field(display => $display) if !$user_obj;
					
					if(!$user_obj)
					{
						$user_obj = AppCore::User->insert({
							user	=> $email,
							email	=> $email,
							display	=> $display,
							pass 	=> $token,
							first 	=> $first,
							'last'	=> $last,
							fb_user => $fb_user,
							location=> $local,
							tz_off  => $tz_off,
						});
						
						print STDERR "Created new user from facebook data: $display - $email, userid $user_obj\n"; 
					}
					else
					{
						print STDERR "Matched facebook user to existing user: $display - $email, userid $user_obj\n";
						
						$user_obj->first($first) if !$user_obj->first;
						$user_obj->last($last)   if !$user_obj->last;
						$user_obj->location($local)  if !$user_obj->location;
						$user_obj->fb_user($fb_user) if !$user_obj->fb_user;
						$user_obj->tz_off($tz_off)   if !$user_obj->tz_off;
					}
					
					my $photo_url = 'https://graph.facebook.com/me/picture?type=square&access_token='.$token;
					my $photo = LWP::Simple::get($photo_url);
					my $local_photo_url = "/mods/" . __PACKAGE__ . "/user_photos/user". $user_obj->id .".jpg";
					my $file_path = $AppCore::Config::APPCORE_ROOT . $local_photo_url;
					if(open(PHOTO, '>' . $file_path))
					{
						print PHOTO $photo;
						close(PHOTO);
						
						$user_obj->photo($local_photo_url);
						
						print STDERR "Downloaded user photo to $file_path.\n";
					}
					else
					{
						print STDERR "Error opening $file_path for writing: $!";
					}
					
					
					$user_obj->is_fbuser(1);
					$user_obj->fb_token($token);
					$user_obj->fb_token_expires($expires);
					$user_obj->update;
					
					if(AppCore::AuthUtil->authenticate($user_obj->user, $token))
					{
						my $url_from = $AppCore::Config::WELCOME_URL; # if !$url_from  || $url_from =~ /\/(login|logout)/;
						print STDERR "Authenticated ".AppCore::Common->context->user->display." with facebook token $token, redirecting to $url_from\n";
						return $r->redirect($url_from);
					}
					else
					{
						return $r->error("Facebook API Error","Unable to connect facebook data to local account.");
					}
				}
				else
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
		
		#print STDERR "auth($sub_page): ".Dumper($req,$page);
			
		if($action eq 'facebook')
		{
			return $self->connect_with_facebook($req,$r);
		}
		
		if($action eq 'authenticate' && AppCore::AuthUtil->authenticate($req->{user},$req->{pass})) #,1))
		{
			my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
			$url_from = $AppCore::Config::WELCOME_URL if !$url_from  || $url_from =~ /\/(login|logout)/;
			print STDERR "Authenticated ".AppCore::Common->context->user->display.", redirecting to $url_from\n";
			return $r->redirect($url_from);
		}
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		# Fell thru from auth attempt, so check to see if it has a user but no password
		if($action eq 'authenticate')
		{
			print STDERR "auth fall thru: mark1\n";
			my $user = AppCore::User->by_field(user=>$req->{user});
			if($user && !$user->pass)
			{
				my $url = $self->module_url($SIGNUP_ACTION) . '?user='.AppCore::Common->url_encode($user->user);
				print STDERR "auth fall thru: mark2: $url\n";
				return $r->redirect($url);
			}
			print STDERR "auth fall thru: mark3\n";
		}
			
		
		if(AppCore::Common->context->user)
		{
			AppCore::AuthUtil->logoff;
			
			print STDERR "auth logoff\n";
			
			# Redirect back here inorder for any user-dependent template features to adjust given the logout
			return $r->redirect($self->module_url($LOGIN_ACTION) . '?url_from='.$url_from.'&was_loggedin=1');
		}
		
		#print STDERR "auth tmpl output\n";	
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('login'.($mobile?'-mobile' : '').'.tmpl');
		#$tmpl->param(challenge => AppCore::AuthUtil->get_challenge());
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		$tmpl->param(was_loggedin => $req->{was_loggedin});
		$tmpl->param(sent_pass    => $req->{sent_pass});
		$tmpl->param(fb_app_id	  => $AppCore::Config::FB_APP_ID);
		$tmpl->param(fb_redir_url => $self->get_facebook_redir_url());
		#$tmpl->param(auth_requested => $req->{auth_requested});
		# Shouldn't get here if login was ok (redirect above), but since we're here with the authenticate page, assume they failed login
		$tmpl->param(bad_login => 1) if $action eq 'authenticate';
		
		
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


		my $name_short = $AppCore::Config::WEBSITE_NAME;
		my $name_noun  = $AppCore::Config::WEBSITE_NOUN;
		my @admin_emails = @AppCore::Config::ADMIN_EMAILS;

		if($sub_page eq 'post')
		{
			my $name = $req->{name};
			my $email = $req->{user};
			my $pass = $req->{pass};
			
			my $signup_ok = 0;
			
			my $user = AppCore::User->by_field(email=>$email);
			$user = AppCore::User->by_field(user=>$email) if !$user;
			if($user && !$user->pass)
			{
				print STDERR MY_LINE()."auth($sub_page): mark: case 1 ($user)\n";
				$signup_ok = 1;
				$user->pass($pass);
				$user->email($email);
				$user->user($email);
				$user->display($name) if $name;
				$user->update;
				
				AppCore::AuthUtils->authenticate($user,$pass);
				
				
				AppCore::Common->send_email(\@admin_emails,"[$name_short] User Activated: $email","User '$email', name '$name' has now activated their account.");
				AppCore::Common->send_email([$user->email],"[$name_short] Welcome to $name_noun!","You've successfully activated your $name_noun account!\n\n" . ($AppCore::Config::WELCOME_URL ? "Where to go from here:\n\n    ".$AppCore::Config::WELCOME_URL:""));
			}
			elsif(!$user)
			{
				print STDERR MY_LINE()."auth($sub_page): mark: case2\n";
				$signup_ok = 1;
				
				my $user_ref = AppCore::User->insert({user=>$email,email=>$email,display=>$name,pass=>$pass});
				AppCore::AuthUtil->authenticate($email,$pass);
				
				AppCore::Common->send_email(\@admin_emails,"[$name_short] New User: $email","New user '$email', name '$name' just signed up!");
				AppCore::Common->send_email([$user_ref->email],"[$name_short] Welcome to $name_noun!","You've successfully signed up for your personalized $name_noun account!\n\n" . ($AppCore::Config::WELCOME_URL ? "Where to go from here:\n\n    ".$AppCore::Config::WELCOME_URL:""));
			}
			
			if($signup_ok)
			{
				print STDERR MY_LINE()."auth($sub_page): mark: signup_ok\n";
				#my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
				#$url_from = AppCore::Common->context->http_bin.'/welcome' if !$url_from;
				my $url_from = $AppCore::Config::WELCOME_URL;
				return $r->redirect($url_from);
			}
		}
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('signup'.($mobile?'-mobile' : '').'.tmpl');
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		
		my $user = AppCore::User->by_field(user=>$req->{user});
		if($user && !$user->pass)
		{
			$tmpl->param(name => $user->display);
		}
		
		# Shouldn't get here if signup was ok
		$tmpl->param(email_exists => 1) if $sub_page eq 'post';
		
		#$r->output($tmpl);
		$view->output($tmpl);
		
		return $r;
	}


	sub forgot_pass
	{
		my $self = shift;
		my $req = shift;
		my $r = shift;
		
		my $sub_page = $req->next_path;
		
		#print STDERR "auth($sub_page): ".Dumper($req,$page);
		my $name_short = $AppCore::Config::WEBSITE_NAME;
		my $name_noun  = $AppCore::Config::WEBSITE_NOUN;
		my @admin_emails = @AppCore::Config::ADMIN_EMAILS;
		
		if($sub_page eq 'post')
		{
			my $email = $req->{user};
			
			my $user = AppCore::User->by_field(email=>$email);
			if($user && $user->pass)
			{
				AppCore::Common->send_email(\@admin_emails,"[$name_short] User Forgot Password: $email","User '$email' forgot their password.\n\nCorrect password is:\n\n    ".$user->pass);
				
				my $url_from = $self->module_url($LOGIN_ACTION) . '?url_from='.$req->{url_from}.'&sent_pass=1&user='.AppCore::Web::Common->url_encode($email);
				
				AppCore::Common->send_email([$user->email],"[$name_short] Forgotten Password","You or someone using your email requested your password. Your password is:\n\n    ".$user->pass."\n\nYou may enter your password at:\n\n    $url_from\n\n");
				
				return $r->redirect($url_from);
			}
		}
		
		my $url_from = AppCore::Web::Common->url_encode(
					AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $self->get_template('forgot_pass'.($mobile?'-mobile' : '').'.tmpl');
		$tmpl->param(url_from  => $url_from);
		$tmpl->param(user      => $req->{user});
		
		# Shouldn't get here if signup was ok
		$tmpl->param(invalid_email => 1) if $sub_page eq 'post';
		
		$view->output($tmpl);
		
		return $r;
	}
	
	sub profile
	{
		my ($class,$skin,$r,$page,$req,$path) = @_;
		
		my $sub_page = shift @$path;
		
		#AppCore::User::Auth->require_authentication;
		if(!AppCore::Common->context->user)
		{
			$r->redirect(AppCore::Common->context->http_bin.'/login');
		}
		
		if($sub_page eq 'post')
		{
			my $name = $req->{name};
			my $email = $req->{new_user_value};
			my $pass = $req->{new_pass_value};
			
			my $user = AppCore::Common->context->user;
			$user->pass($pass) if $pass && $pass !~ /^\*+$/;
			$user->email($email) if $email;
			$user->user($email) if $email;
			$user->display($name) if $name;
			if($user->is_changed)
			{
				$user->update;
				AppCore::User::Auth->authenticate($req,1);
				
				# Re-apply 'user_' template variables, since they were applied in the load_template() call and won't see the updates we just saved
				$skin->param('user_'.$_ => $user->get($_)) foreach $user->columns
			}
		}
		
		my $mobile = getcookie('mobile.sitepref') eq 'mobile';
		
		my $tmpl = $skin->load_template('profile'.($mobile?'-mobile' : '').'.tmpl');
		$tmpl->param('profile_saved' => 1) if $sub_page eq 'post';
		$tmpl->param(fake_pass => join '', ('*') x length(AppCore::Common->context->user->pass));
		
		$r->output($tmpl);
	}
	
	sub unsubscribe
	{
		my ($class,$skin,$r,$page,$req,$path) = @_;
		
		my $sub_page = shift @$path;
		
		AppCore::User::Auth->require_authentication;
			
	}
}