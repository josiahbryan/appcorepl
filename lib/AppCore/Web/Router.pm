=begin docs

Example usage of AppCore::Web::Router:

#!/usr/bin/perl

use lib '/opt/foobar/lib';
BEGIN { require '/opt/foobar/conf/appcore.pl' };
use strict;

use AppCore::Common;

package RouterDemo;
{
	use strict;
	use base 'AppCore::Web::Controller';
	
	use AppCore::Common;
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		my $router = $self->router;
		
		$router->route(':driverid/:action'	=> {
			':driverid'	=> {
				regex	=> qr/^\d+$/,
				check	=> sub {
					my ($router, $driverid) = @_;
					#print STDERR "Validating driverid '$driverid'\n";
					#my $driver = Foobar::Driver->retrieve($driverid) || die "Invalid driver ID $driverid\n";
					#$router->stash->{driver} = $driver;
					$router->stash->{driver} = $driverid;
				},
			},
			':action'	=> [
				edit		=> 'page_driver_edit',
				post		=> 'page_driver_post',
				delete		=> 'page_driver_delete',
				''		=> 'page_driver_view',
			],
		});
		
		$router->route('new'		=> 'page_driver_new');
		$router->route(''		=> 'page_driver_list');
		
		$router->route(':driverid/email' => 'page_driver_email');
		
		$router->dispatch($ENV{PATH_INFO} || '1234/email');
	}
	
	sub page_driver_list
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver List '.scalar(date())), "\n";
	}
	
	sub page_driver_view
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver View '.scalar(date())), "\n";
	}
		
	sub page_driver_new
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver New '.scalar(date())), "\n";
	}
	
	sub page_driver_edit
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver Edit # '.$class->stash->{driver}.' at '.scalar(date())), "\n";
	}
	
	sub page_driver_post
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver Post # '.$class->stash->{driver}.' at '.scalar(date())), "\n";
	}
	
	sub page_driver_delete
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver Delete # '.$class->stash->{driver}.' at '.scalar(date())), "\n";
	}
	
	sub page_driver_email
	{
		my ($class) = @_;
		
		print join "\n\n", ('text/plain', 'Driver Email # '.$class->stash->{driver}.' at '.scalar(date())), "\n";
	}
}

RouterDemo->new;

=cut

package AppCore::Web::Router::Branch;
{
	use strict;
	use base 'AppCore::SimpleObject';
	
	sub new 
	{
		my $class = shift;
		my %args = @_;
		
		#$args{leafs} = {};
		
		return bless { %args }, $class;
	}
	
	sub leafs  { shift->{leafs} }
	#sub branch { shift->_accessor('branch',    @_) } # => AppCore::Web::Router::Branch
	
	sub num_leafs
	{
		scalar keys ( %{ shift->{leafs} } );
	}
	
	sub has_leafs
	{
		shift->num_leafs > 0;
	}
	
	sub key       { shift->_accessor('key',       @_) }
	sub condition { shift->_accessor('condition', @_) }
	sub validator { shift->_accessor('validator', @_) }
	
	sub leaf
	{
		my $self = shift;
		my $key = shift;
		
		$self->{leafs} ||= {};
		
		return $self->{leafs}->{$key};
	}
	
	sub add_leaf
	{
		my $self = shift;
		my $leaf = shift;
		
		$self->{leafs} ||= {};
		
		$self->leafs()->{$leaf->key} = $leaf;
	}
	
	sub remove_leaf
	{
		my $self = shift;
		my $leaf = shift;
		
		$self->{leafs} ||= {};
		
		delete $self->{leafs}->{$leaf->key};
	}
};

package AppCore::Web::Router::Leaf;
{
	use strict;
	use base 'AppCore::Web::Router::Branch';
	
	sub namespace { shift->_accessor('namespace', @_) }
	sub action    { shift->_accessor('action',    @_) }
};



1;

package AppCore::Web::Router;
{
	use strict;
	use AppCore::Common;
	use AppCore::Web::Request;
	
	sub new
	{
		my $class = shift;
		
		@_ = ( class => shift ) if @_ == 1;
		
		my %args = @_;
		
		$args{root_branch} = AppCore::Web::Router::Branch->new();
		$args{stash}       = $args{class}->stash if $args{class} && $args{class}->can('stash');
		$args{stash}     ||= AppCore::SimpleObject->new();
		
		return bless { %args }, $class;
	}
	
	sub class { shift->{class} }
	sub stash { shift->{stash} }
	
	sub output {
		#print STDERR join "", @_;
	}
	
	sub has_routes
	{
		shift->{root_branch}->has_leafs;
	}
	
	
	sub route
	{
		my ($self, $route, $args) = @_;
		
		$args = { action => $args } if !ref $args;
		
		my $class = $self->class;
		
		# We want to be able to use a blessed ref as namespace for calls so we dont grab the class the ref
		#$class = ref $class if ref $class;
		
		#output "route: $route, args: ".Dumper($args)."\n";
		
		# Split the route into individual parts because we want to separate
		# the last part of the route (the leaf) from the preceeding parts (branches)
		my @parts = split /\//, $route;
		
		# The last item in the route is the leaf - there will always be at least one element in
		# @parts - even with an empty string ''
		my $leaf_key = pop @parts;
		
		# As we go thru the @parts, we will add brnaches to the previous branch.
		# So we need to start with something - every call to route() starts with the root branch
		my $last_branch = $self->{root_branch};
		
		# Go thru each part in the list of branch @parts and build branch objects
		foreach my $branch_key (@parts)
		{
			my $branch_args = $args->{$branch_key};
			
			# If a branch by the same name already exists in the current ($last_branch) branch
			# then reuse the object - we'll merge arguments (overriding) as necessary
			my $branch = $last_branch->leaf($branch_key)
				# Otherwise, if no same-named branch exists, create a new one
				|| AppCore::Web::Router::Branch->new( key => $branch_key );
			
			# Check branch args and update $branch accordingly
			if($branch_args)
			{
				$branch->condition($branch_args->{regex} || $branch_args->{condition})
						if $branch_args->{regex} || $branch_args->{condition};
				
				$branch->validator($branch_args->{check} || $branch_args->{validator})
						if $branch_args->{check} || $branch_args->{validator};
			}
			
			# Add the current branch to $last_branch (will override same-named branches,
			# hence why we pull the existing $branch if one exists, above)
			$last_branch->add_leaf($branch);
			
			# Store this $branch as $last_branch for the next branch we create (or the leaf)
			$last_branch = $branch;
		}
		
		#my $leaf_args = @parts && !$args->{action}
		#	? $args->{$leaf_key}
		#	: $args;
		
		my $leaf_args = $args->{action} || ref $args eq 'ARRAY' ? $args : $args->{$leaf_key};
		
		#output "leaf_key: $leaf_key, args: ".Dumper($leaf_args)."\n";
		
		# There are three types of ways to specify a leaf:
		# # 1.
		# $router->route('new'	=> 'page_driver_new');
		# # 2.
		# $router->route('new'	=> {
		# 	'action' => 'page_driver_new',
		#	'namespace' => 'Foobar'
		# });
		# # 3.
		# $router->route(':action'	=> [
		#		edit		=> 'page_driver_edit',
		#		post		=> 'page_driver_post',
		# 	]
		# );
		# # 3b.
		# $router->route(':action'	=> {
		#	':action'	=> [ 
		#		edit		=> 'page_driver_edit',
		#		post		=> 'page_driver_post',
		# 	]
		# })
		# 
		# Call 1 is obvious - /new goes to page_driver_new() in the $class associated with $router (when $router was created)
		# Call 2 is also obvious - /new goes to Foobar::page_driver_new()
		# Call 3 is kind of obvious - /(edit|post) are accepted and go to page_driver_edit or page_driver_post (respectively) on the associated $class
		#     (3b is just a variant on 3)
		#
		
		if(ref $leaf_args eq 'ARRAY')
		{
			#my %options = %{@{$leaf_args || []}};
			my @leaf_arg_list = @$leaf_args;
			my %options = ( @leaf_arg_list );
			
			foreach my $option_key (keys %options)
			{
				my $leaf = AppCore::Web::Router::Leaf->new( key => $option_key );
				
				$leaf->action($options{$option_key});
				$leaf->namespace($class);
				
				$last_branch->add_leaf($leaf);
			}
			
			$last_branch->{_limited_leaf} = 1;
		}
		elsif(ref $leaf_args eq 'HASH')
		{
			my $leaf = AppCore::Web::Router::Leaf->new( key => $leaf_key );
				
			$leaf->action($leaf_args->{action});
			$leaf->namespace($leaf_args->{namespace} || $class);
			
			$leaf->condition($leaf_args->{regex} || $leaf_args->{condition})
				      if $leaf_args->{regex} || $leaf_args->{condition};
			
			$leaf->validator($leaf_args->{check} || $leaf_args->{validator})
				      if $leaf_args->{check} || $leaf_args->{validator};
			
			$last_branch->add_leaf($leaf);
		}
		else
		{
			my $leaf = AppCore::Web::Router::Leaf->new( key => $leaf_key );
				
			$leaf->action($leaf_args);
			$leaf->namespace($class);
			
			$last_branch->add_leaf($leaf);
		}
	
	}
	
	sub _call
	{
		my $self = shift;
		my $leaf = shift;
		
		my $package = $leaf->namespace;
		my $method  = $leaf->action;
		
		output("_call: leaf key: $leaf->{key}, method: $method ($package)\n");
		
		if(!$package)
		{
			warn "No namespace on this leaf: ".Dumper($leaf);
			return;
		}
		if(!$method)
		{
			warn "No action on this leaf: ".Dumper($leaf);
			return;
		}
		
		my $ref;
		
		if(ref $package)
		{
			$ref = $package;
		}
		else
		{
			eval('use '.$package);
			undef $@;
			
# 			if($package->can('new'))
# 			{
# 				$ref = $package->new();
# 				$self->{_cache}->{$package} = $ref;
# 			}
# 			else
# 			{
				$ref = $package;
#			}
		}
		
		$ref->$method();
	}
	
	sub dispatch
	{
		my $self = shift;
		my $req = shift;
		
		$req = AppCore::Web::Request->new(PATH_INFO => $req)
			if $req && !ref $req;
			
		#print Dumper $req;

		$req = $self->class->stash->{req}
			if !$req &&
			   $self->class &&
			   $self->class->can('stash') &&
			   $self->class->stash;
		
		#output "dispatch: $np\n";
		
		my $root = $self->{root_branch};
		
		if(!$root)
		{
			warn __PACKAGE__."::dispatch: Unable to dispatch: No root branch, call route() before dispatch() to setup routes";
			return;
		}
		
		$self->_match_branch($root, $req);
	}
	
	sub _match_branch
	{
		my $self = shift;
		my $branch = shift;
		my $req = shift;
		my $np = $req->next_path;
		
		output("_match_branch: np: $np, branch key: ".$branch->key."\n");
		
		if($branch->{action})
		{
			output("\t -> no leafs match, trying to call branch action '$branch->{action}\n");
			return $self->_call($branch);
		}
		else
		{
			my $leafs = $branch->leafs;
			
			output("\t -> checking leafs ... \n");
			
			if(my $next_branch = $leafs->{$np})
			{
				output("\t -> found next branch directly via {key}...\n");
				
				$req->shift_path;
				$req->push_page_path($np);
			
				#$self->_call($branch);
				return $self->_match_branch($next_branch, $req);
			}
			else
			{
				foreach my $next_branch (values %$leafs)
				{
					if($next_branch->condition && 
					   $np =~ $next_branch->condition)
					{
						output("\t -> found next branch via {condition}...\n");
						
						$next_branch->validator()->($self, $np)
							if $next_branch->validator;
						
						$req->shift_path;
						$req->push_page_path($np);
						
						return $self->_match_branch($next_branch, $req);
					}
				}
			}
			
			# If we hit this statement, it means we didn't match by key or condition...
			
			if(!$branch->{_limited_leaf} &&
			   $leafs->{''})
			{
				output("\t -> fall thru to empty leaf, found empty leaf on this branch to call...\n");
				
				$req->shift_path;
				$req->push_page_path($np);
			
				return $self->_call($leafs->{''});
			}
			else
			{
				die "Invalid page '$np' (".$req->page_path.'/'.join('/',$req->path_info).")";
			}
		}
	}

};
1;