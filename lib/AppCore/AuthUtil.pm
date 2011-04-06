# Package: AppCore::Auth::Util
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
	sub debug { } #print STDERR __PACKAGE__.": ".join("",@_)."\n" unless get_full_url =~ /res\//; } 
	
	sub _cdbi_load_all_columns
	{
		my $ent = shift;
		return $ent if !$ent; 
		local $_;
		$ent->{$_} = $ent->get($_) foreach $ent->columns;
		return $ent;
	}
	
	sub logoff
	{
		
		my $ctx = AppCore::Common->context;
		#session(TICKET_COOKIE,undef);
		
		my $old_user = $ctx->user;
		$ctx->user(undef);
		
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
		
		AppCore::Auth::Util::http_require_login() if !AppCore::Auth::Util::authenticate();
		
		if(my $user = AppCore::Common->context->user)
		{
			my $acl = shift;
			if($acl && !$user->check_acl($acl))
			{
				AppCore::Web::Common::error("Access Denied","Sorry, the page you're trying to access has restricted access.");
			}
		}
		
		return 1;
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
		
		my $args = $ctx->http_args || {};
		
		my $user = shift; # || $args->{user};
		my $pass = shift; # || $args->{pass};
	
		if(!$user && !$pass)
		{
			my $sec = $ENV{APPCORE_AUTH};
			($user,$pass) = split /:/, $sec;
		}
		
		my $redirect = shift;
		
		my $tk = getcookie(TICKET_COOKIE); #session(TICKET_COOKIE); #getcookie(TICKET_COOKIE); #$ctx->auth_ticket;
		
		debug("\$tk = '$tk'");
		my ($tk_user,$tk_pass) = $tk =~ /^(.*)\.([^\.]+)$/;
		$user||=$tk_user;
		$pass||=$tk_pass;
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
		}
		
		my $user_object = AppCore::User->by_field(user => $user);
		if(!$user_object)
		{
			$user_object = AppCore::User->by_field(email => $user);
		}
		
		my $hash = md5_hex(join('',$user,$user_object?$user_object->pass:undef,$ENV{REMOTE_ADDR}));
		#debug("target hash='$hash', target pass='".$user_object->pass."'");
		if($user_object && $user && ($user_object->pass eq $pass || $hash eq $pass || $user_object->fb_token eq $pass))
		{
			$ctx->user($user_object);
			if(!$tk)
			{
				$tk = join('.',$user,$hash);
				setcookie(TICKET_COOKIE,$tk);
				#session(TICKET_COOKIE,$tk);
				#AppCore::Session->save;
			}
			
			debug("authenticating '$user', returning true");
			return _cdbi_load_all_columns($ctx->user);
		}
		else
		{
			debug("no auth, resetting context user");
			$ctx->user(undef);
			if(!$redirect)
			{
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
		my $extra;
		if(@_)
		{
			my %hash = @_;
			$extra = '&' . join('&', map { $_ => url_encode($hash{$_}) } sort keys %hash );
		}
		my $url = $AppCore::Config::LOGIN_URL.'?url_from='.url_encode(get_full_url()).$extra;
		redirect($url);
	}
};

1;
