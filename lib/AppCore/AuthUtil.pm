# Package: AppCore::AuthUtil
# Utility methods for authentication using <AppCore::Auth::Entity>.
package AppCore::AuthUtil;
{
	
	use strict;
	use AppCore::User;
	use AppCore::Web::Common;
	use AppCore::Common;
	use AppCore::DBI;
	#use AppCore::Session;
	
	use Data::Dumper;
	
	use Digest::MD5 qw/md5_hex/;
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/authenticate http_require_login require_auth/;
		
	use constant TICKET_COOKIE => 'appcore.auth_ticket';
	sub debug {}# print STDERR __PACKAGE__.": ".join("",@_)."\n" unless get_full_url =~ /res\//; }
	#sub debug { print STDERR __PACKAGE__.": ".join("",@_)."\n" unless get_full_url =~ /res\//; }
	 
	
	sub _cdbi_load_all_columns
	{
		my $ent = shift;
		return $ent if !$ent; 
		
		my @columns = $ent->columns;
		
		local $_;
		$ent->{$_} = $ent->get($_) foreach @columns;
		
		return $ent;
	}
	
	sub logoff
	{
		
		my $ctx = AppCore::Common->context;
		#session(TICKET_COOKIE,undef);
		
		my $old_user = $ctx->user;
		$ctx->user(undef);
		$ctx->auth_ticket(undef);
		
		if(getcookie(TICKET_COOKIE))
		{
			#print STDERR "Debug: logoff(): Setting cookie '".TICKET_COOKIE."' to '0'\n";
			setcookie(TICKET_COOKIE,'0');
			return 1;
		}
		else
		{
			return 0;
		}
		
		return 1 if $old_user;
		
	}
	
	
	sub require_auth
	{
		my $self = shift;
		
		AppCore::AuthUtil::http_require_login() if !AppCore::AuthUtil::authenticate();
		
		if(my $user = AppCore::Common->context->user)
		{
			my $acl = shift;
			#use Data::Dumper;
			#print STDERR "ACL: ".Dumper($acl,$user);
			if($acl && !$user->check_acl($acl))
			{
				AppCore::Web::Common::error("Access Denied","Sorry, the page you're trying to access has restricted access.");
			}
		}
		
		return 1;
	}
	
	sub parse_ticket
	{
		#shift if $_[0] eq __PACKAGE__;
		my ($class, $tk) = @_;
		
		#print STDERR $class."::parse_ticket: ",$tk;
		#my $tk = shift;
		
		my ($tk_user,$tk_pass) = $tk =~ /^(.*)\.([^\.]+)$/;
		return {
			user => $tk_user,
			pass => $tk_pass
		};
	}
	
	
	sub authenticate
	{
		my $ctx = AppCore::Common->context;
	# 	
	# 	if($ENV{REMOTE_ADDR} eq '10.0.1.6')
	# 	{
	# 		AppCore::Common->context->user(AppCore::Auth::Entity->retrieve(1));
	# 		return 1;
	# 	}
	# 	
		#AppCore::Session->load;
		
		shift if $_[0] eq __PACKAGE__;
		
		my $ADMIN_GROUP = AppCore::User::Group->find_or_create({name => 'ADMIN'});
	
		# If no users created in the database, create a default user
		if(!AppCore::User->sql_single('COUNT(userid)')->select_val)
		{
			my $admin = AppCore::User->insert({
				user    => 'admin',
				pass    => 'admin',
				display => 'Administrator',
				email   => AppCore::Config->get('WEBMASTER_EMAIL'),
			});
			
			AppCore::User::GroupList->insert({
				userid  => $admin,
				groupid => $ADMIN_GROUP
			});
		}
		
		my $args = $ctx->http_args || {};
		
		my $user = shift;# || $args->{user};
		my $pass = shift;# || $args->{pass};
	
		if(!$user && !$pass)
		{
			my $sec = $ENV{APPCORE_AUTH};
			($user,$pass) = split /:/, $sec;
		}
		
		my $redirect = shift;
		
		my $tk = getcookie(TICKET_COOKIE) || $args->{auth_ticket}; #session(TICKET_COOKIE); #getcookie(TICKET_COOKIE); #$ctx->auth_ticket;
		#print STDERR "authenticate(): cookie:'$tk'\n";
		
		debug("cookie = '$tk'");
		
		my $ticket = __PACKAGE__->parse_ticket($tk);
		
		$user||=$ticket->{user};
		$pass||=$ticket->{pass};
		
		$user = $args->{user} if !$user;
		$pass = $args->{pass} if !$pass;
		
		# Check the "lkey" if given
		if($args->{lkey} &&
		   !$user && !$pass)
		{
			my $lkey = $args->{lkey};
			my $userobj = AppCore::User->by_field(lkey => $lkey);
			if($userobj)
			{
				$user = $userobj->user;
				$pass = $userobj->pass;
				
				# Found user object, but the user never set a user or password
				if(!$user && !$pass)
				{
					# The actual "authentication" takes place lower in the code,
					# just setup the values here
					$user = "user".$userobj->id;
					$pass = $userobj->id + 3729;
					
					$userobj->user($user);
					$userobj->pass($pass);
					$userobj->update;
				}
				
				# Prevent auto-login for Admins
				if($userobj->check_acl(['ADMIN']))
				{
					undef $user;
					undef $pass;
				}
				else
				{
					# We've put the user/pass in $user/$pass for checking below,
					# now we just reset the lkey so the lkey login only works once
					$userobj->clear_lkey();
				
					print STDERR "Auto-login via lkey for ".$userobj->display.", lkey: $args->{lkey}\n";
				}
			}
		}
		
		debug("user='$user',pass='$pass'");
		
		if(!$user && !$pass)
		{
			# Compatability with the old legacy intranet authentication framework
			#$user = getcookie('user');
			#$pass = getcookie('pass');
			
			# Don't empty out old cookie - because on a no_header request, the Legacy module
			# will redirect back to /legacy_web.cgi, which needs those cookies still to authenticate
			# the request.....
			#setcookie('user','0'); # empty out the old cookies
			#setcookie('pass','0'); # empty out the old cookies
			#print STDERR "authenticate: Empty user and empty pass\n";
			
			$@ = "authenticate: Empty user and empty pass";
			
			return 0;
		}
		
		#print STDERR "authenticate: user '$user', pass '$pass'\n";
		my $user_object = AppCore::User->by_field(user => $user, deleted => 0);
		#print STDERR "authenticate: user '$user', mark1 obj '$user_object'\n";
		if(!$user_object)
		{
			$user_object = AppCore::User->by_field(email => $user, deleted => 0);
		}
		#print STDERR "authenticate: user '$user', mark2 obj '$user_object'\n";
		
		if(!$user_object)
		{
			$user_object = AppCore::User->sync_from_ad($user);
		}
		
		if(!$user_object)
		{
			print STDERR "authenticate: No AppCore::User found matching '$user'\n";
			return 0;
		}
		
		#print STDERR "authenticate: user '$user', expected pass '".$user_object->pass."'\n";
		
		my $hash = md5_hex(join('', $user, $user_object ? $user_object->pass:undef)); #,$ENV{REMOTE_ADDR}));
		
		debug("\$user_object='$user_object', target hash='$hash', target pass='".$user_object->pass."', user=[$user], pass=[$pass], fb_token:".$user_object->fb_token);
		if($user_object &&
		   $user_object->pass &&
		   $user &&
		   $pass && 
		   (
			$pass eq $user_object->pass || 
			$pass eq $hash              || 
				($user_object->fb_token &&
				 $user_object->fb_token eq $pass) 
						    ||
			$user_object->try_ad_auth($user, $pass)
		   )
		)
		{
			# Create our auth_ticket using the md5 hashed user/pass
			$tk = join('.',$user,$hash);
			setcookie(TICKET_COOKIE,$tk);
			
			# Store auth_ticket in Context for use elsewhere, such as cross-app authentication (e.g. SocketCluster)
			$ctx->auth_ticket($tk);
		
			# Set the current user on the context
			$ctx->user($user_object);
			
			#session(TICKET_COOKIE,$tk);
			#AppCore::Session->save;
			
			debug("authenticating '$user', returning true");
			return _cdbi_load_all_columns($ctx->user);
		}
		else
		{
			debug("no auth, resetting context user");
			$ctx->user(undef);
			if(!$redirect)
			{
				print STDERR "authenticate: userid $user_object could not match given user/pass: [$user] / [$pass]\n";
				return 0;
			}
			else
			{
				http_require_login();
			}
		}
		
		
	}
	
	sub http_require_login
	{
		my $ctx = AppCore::Common->context;
		if(my $user = $ctx->current_request->{user})
		{
			#$user =~ s/\+/\%2B/g; # manually encode '+'
			
			push @_, (user => $user);
			print STDERR "http_require_login: user: $user\n";
		}
		
		my $extra;
		if(@_)
		{
			my %hash = @_;
			$extra = '&' . join('=', map { $_ => url_encode($hash{$_}) } sort keys %hash );
			print STDERR "http_require_login: extra: $extra\n";
		}
		my $url = ($ctx->{login_url} || AppCore::Config->get("LOGIN_URL")).'?auth_requested=1&url_from='.url_encode(get_full_url()).$extra;
		AppCore::Web::Common->redirect($url);
	}
};

1;
