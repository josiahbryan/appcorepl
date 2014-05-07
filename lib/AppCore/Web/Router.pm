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
	
	sub new
	{
		my $class = shift;
		my %args = @_;
		
		#die Dumper \%args;
		
		return bless { %args }, $class;
	}
	
	sub class { shift->{class} }
	sub stash { shift->{stash} }
	
	sub output {
		#print STDERR join "", @_;
	}
	
	
	sub route
	{
		my ($self, $route, $args) = @_;
		
		my $class = $self->class;
		
		$args = { action => $args } if !ref $args;
		
		#output "route: $route, args: ".Dumper($args)."\n";
		
		
		$self->{root_branch} ||= AppCore::Web::Router::Branch->new( key => '' );
		my $root = $self->{root_branch};
		
# 		if($route =~ /\//)
# 		{
			my @parts = split /\//, $route;
			
			my $leaf_key = pop @parts;
			
			my $last_branch = $root;
			
			foreach my $branch_key (@parts)
			{
				my $branch_args = $args->{$branch_key};
				
				my $branch = $last_branch->leaf($branch_key)
					|| AppCore::Web::Router::Branch->new( key => $branch_key );
				
				if($branch_args)
				{
					$branch->condition($branch_args->{regex} || $branch_args->{condition})
						        if $branch_args->{regex} || $branch_args->{condition};
					
					$branch->validator($branch_args->{check} || $branch_args->{validator})
						        if $branch_args->{check} || $branch_args->{validator};
				}
				
				#$branches{$branch_key} = $branch;
				
				$last_branch->add_leaf($branch);
					
				$last_branch = $branch;
			}
			
			my $leaf_args = @parts && !$args->{action}
				? $args->{$leaf_key}
				: $args;
			
			#output "leaf_key: $leaf_key, args: ".Dumper($leaf_args)."\n";
			
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
		#}
		
		
		#$args->{namespace} ||= ref $class ? ref $class : $class;
		
		#output "route: $route, args: ".Dumper($args)."\n";
# 		
# 		
# 		$self->{_routes_list} ||= [];
# 		$self->{_routes_hash} ||= {};
# 		my $r = $self->{_routes_hash};
# 		
# 		my $list_size = scalar(@{$self->{_routes_list}});
# 		
# 		$args->{_route_index} = $list_size+1;
# 		$r->{$route} = $args;
# 		
# 		my @route_list = map 
# 		{{
# 			name => $_,
# 			args => $r->{$_}
# 		}} keys %$r;
# 		
# 		@route_list = sort { $a->{args}->{_route_index} <=> $b->{args}->{_route_index} } @route_list;
# 		
# 		$self->{_route_list} = \@route_list;
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
			
			if($package->can('new'))
			{
				$ref = $package->new();
				$self->{_cache}->{$package} = $ref;
			}
			else
			{
				$ref = $package;
			}
		}
		
		$ref->$method();
	}
	
	sub dispatch
	{
		my $self = shift;
		my $class = shift || $self->class;
		my $req = $class->stash->{req};
		#my $np = lc $req->next_path;
		
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
			
			if($leafs->{''})
			{
				output("\t -> fall thru to empty leaf, found empty leaf on this branch to call...\n");
				
				$req->shift_path;
				$req->push_page_path($np);
			
				#$self->_call($branch);
				return $self->_call($leafs->{''});
			}
		}
	}

};
1;