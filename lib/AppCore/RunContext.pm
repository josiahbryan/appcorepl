
package AppCore::RunContext;
# Package: AppCore::RunContext
# Runtime context for an EAS module/application - singleton class initalized by the module 
# loader and accessed from AppCore::Common->context.

use strict;
use Data::Dumper;
#use AppCore::Auth::Entity;

sub new 
{
	my $class = shift;
	my %args = @_;
	
	$args{eas_login_mod} ||= 'Login';
	#die Dumper \%args;
	
	return bless { %args }, $class;
}

sub x
{
        my($x,$k,$v)=@_;
        if(defined $v)
        {
        	$x->{$k}=$v;
#         	print STDERR AppCore::Common::MY_LINE().": x('$k') := '$v'\n";
        }

        $x->{$k};
}

sub cgi_setup
{
	my $ctx = shift;
	my ($root,$bin,$x_tmpl_path) = @_;
	
	$ctx->http_root($root);
	$ctx->http_bin($bin);
	$ctx->x('template_path',$x_tmpl_path) if $x_tmpl_path;

	if(!$AppCore::Web::Common::MOD_PERL)
	{
		$ENV{'REMOTE_ADDR'} = $ENV{'HTTP_X_FORWARDED_FOR'} if $ENV{'HTTP_X_FORWARDED_FOR'};

		my $q = CGI->new;
		my %args = $q->Vars;
		
		my $path_info = $ENV{PATH_INFO};
		$path_info =~ s/^\///g;
		#$path_info = '' if $path_info eq 's';
		
		$args{PATH_INFO} = $path_info;
		
		$ctx->http_args(\%args);
		return 1;
	}
	else
	{
		warn "Running under mod_perl, not doing cgi_setup()";
		return 0;
	}
}

sub _reset
{
	my $self = shift;
	delete $self->{$_} foreach keys %$self;
	$self->{eas_login_mod} ||= 'Login';
}


sub current_module	{shift->x('module', @_)}
sub current_user 	{shift->x('user', @_)}
sub current_request	{shift->x('req', @_)}

sub module 		{shift->x('module', @_)}
sub user   		{shift->x('user', @_)}

sub http_root  		{shift->x('http_root',@_)}
sub http_bin   		{shift->x('http_bin',@_)}

#sub auth_ticket		{shift->x('auth_ticket',@_)}

sub http_args		{shift->x('http_args',@_)}

sub mobile_flag		{shift->x('mobile_flag',@_)}


1;
