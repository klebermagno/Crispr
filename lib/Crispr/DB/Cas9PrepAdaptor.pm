## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Cas9PrepAdaptor;
## use critic

# ABSTRACT: Cas9PrepAdaptor object - object for storing Cas9Prep objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use Crispr::DB::Cas9Prep;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::Cas9;
use Crispr::DB::Cas9Prep;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $cas9_prep_adaptor = Crispr::DB::Cas9PrepAdaptor->new(
					driver => 'mysql',
                    host => 'dbhost',
                    port => dbport,
					dbname => 'db_name',
					user => 'dbuser',
					pass => 'dbpassword',
					dbfile => 'test.db',
					connection => $connection,
                );
  Purpose     : Constructor for creating cas9_prep adaptor objects
  Returns     : Crispr::DB::Cas9PrepAdaptor object
  Parameters  :     driver => Str,
                    host => Str,
                    port => Int,
					dbname => Str,
					user => Str,
					pass => Str,
					dbfile => Str,
					connection => DBIx::Connector object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a Cas9PrepAdaptor is to use the
                get_adaptor method with a previously constructed DBAdaptor object

=cut

=method store

  Usage       : $cas9_prep = $cas9_prep_adaptor->store( $cas9_prep );
  Purpose     : Store a cas9_prep in the database
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::DB::Cas9Prep object
  Throws      : If argument is not a Cas9Prep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $cas9_prep, ) = @_;
	# make an arrayref with this one cas9_prep and call store_cas9_preps
	my @cas9_preps = ( $cas9_prep );
	my $cas9_preps = $self->store_cas9_preps( \@cas9_preps );
	
	return $cas9_preps->[0];
}

=method store_cas9_prep

  Usage       : $cas9_prep = $cas9_prep_adaptor->store_cas9_prep( $cas9_prep );
  Purpose     : Store a cas9_prep in the database
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::DB::Cas9Prep object
  Throws      : If argument is not a Cas9Prep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_cas9_prep {
    my ( $self, $cas9_prep, ) = @_;
	return $self->store( $cas9_prep );
}

=method store_cas9_preps

  Usage       : $cas9_preps = $cas9_prep_adaptor->store_cas9_preps( $cas9_preps );
  Purpose     : Store a set of cas9_preps in the database
  Returns     : ArrayRef of Crispr::DB::Cas9Prep objects
  Parameters  : ArrayRef of Crispr::DB::Cas9Prep objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Cas9Prep objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_cas9_preps {
    my $self = shift;
    my $cas9_preps = shift;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Cas9Prep objects.\n" if( ref $cas9_preps ne 'ARRAY');
	foreach ( @{$cas9_preps} ){
        if( !ref $_ || !$_->isa('Crispr::DB::Cas9Prep') ){
            confess "Argument must be Crispr::DB::Cas9Prep objects.\n";
        }
    }
	
    my $statement = "insert into cas9 values( ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($statement);
		
		foreach my $cas9_prep ( @$cas9_preps ){
			$sth->execute($cas9_prep->db_id, $cas9_prep->type,
				$cas9_prep->prep_type, $cas9_prep->made_by, $cas9_prep->date, );
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'cas9', 'cas9_id' );
			$cas9_prep->db_id( $last_id );
		}
		
		$sth->finish();
    } );
    
    return $cas9_preps;
}

=method fetch_by_id

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_by_id( $cas9_prep_id );
  Purpose     : Fetch a cas9_prep given its database id
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : crispr-db cas9_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $statement = "select * from cas9 where cas9_id = ?;";
    my $result;
    eval{ $result = $self->fetch_rows_expecting_single_row( $statement, [ $id ] ); };
    
    my $cas9_prep;
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/NO\sROWS/xms ){
    		confess "Couldn't retrieve cas9_prep, $id, from database.\n";
        }
        elsif( $EVAL_ERROR =~ m/TOO\sMANY\sROWS/xms ){
            confess "Cas9Prep id, $id, should be unique, but I got more than one row returned!\n";
        }
        else{
            confess $EVAL_ERROR, "\n";
        }
    }
    else{
        $cas9_prep = $self->_make_new_cas9_prep_from_db( $result, );
    }
    
    return $cas9_prep;
}

=method fetch_by_ids

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_by_ids( \@cas9_prep_ids );
  Purpose     : Fetch a list of cas9_preps given a list of db ids
  Returns     : Arrayref of Crispr::DB::Cas9Prep objects
  Parameters  : Arrayref of crispr-db cas9_prep ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @cas9_preps;
    foreach my $id ( @{$ids} ){
        push @cas9_preps, $self->fetch_by_id( $id );
    }
	
    return \@cas9_preps;
}

=method fetch_all_by_type_and_date

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type_and_date( $cas9_prep_name, $requestor );
  Purpose     : Fetch a cas9_prep given a cas9_prep name
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : crispr-db cas9_prep name - Str
                requestor - Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_type_and_date {
    #my ( $self, $cas9_prep_type, $date ) = @_;
    #
    #my $statement = "select * from cas9_prep where cas9_prep_name = ? and requestor = ?;";
    #my $cas9_prep;
    #eval{
    #    my $results = $self->fetch_rows_expecting_single_row( $statement, [ $cas9_prep_name, $requestor, ], );
    #    $cas9_prep = $self->_make_new_cas9_prep_from_db( $results );
    #};
    #if( $EVAL_ERROR ){
    #    if( $EVAL_ERROR eq 'NO ROWS' ){
    #        confess "Couldn't retrieve cas9_prep, $cas9_prep_name, from database.\n";
    #    }
    #    elsif( $EVAL_ERROR eq 'TOO MANY ROWS' ){
    #        confess "Cas9Prep name, $cas9_prep_name, should be unique, but I got more than one row returned!\n";
    #    }
    #    else{
    #        confess "$cas9_prep_name: $EVAL_ERROR\n";
    #    }
    #}
    #
    #return $cas9_prep;
}

=method fetch_all_by_type

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type( $crRNA );
  Purpose     : Fetch a cas9_prep given a crRNA object
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::crRNA object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_type {
	#my ( $self, $type, ) = @_;
#    my $dbh = $self->connection->dbh();
#	
#	# try to retrieve cas9_prep by id first then name
#    my $cas9_prep;
#    if( defined $crRNA->cas9_prep_id ){
#        $cas9_prep = $self->fetch_by_id( $crRNA->cas9_prep_id );
#        
#    }
#    elsif( defined $crRNA->cas9_prep_name &&
#            defined $crRNA->requestor ){
#        $cas9_prep = $self->fetch_by_name_and_requestor( $crRNA->cas9_prep_name, $crRNA->requestor );
#    }
#    
#    return $cas9_prep;
}

=method fetch_all_by_date

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_all_by_date( $crRNA );
  Purpose     : Fetch a cas9_prep given a crRNA object
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::crRNA object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_date  {
    #my ( $self, $date ) = @_;
#	my $statement = "select * from cas9_prep where date_created = ?";
#	
#    my $dbh = $self->connection->dbh();
#    my @cas9_preps;
#    $self->connection->txn(  fixup => sub {
#	my $sth = $dbh->prepare($statement);
#	my $num_rows;
#    $num_rows = $sth->execute( $date );
#	
#	if( $num_rows == 0 ){
#	    die "There are no cas9_preps created on ", $date, ".\n";
#	}
#	else{
#	    while( my @fields = $sth->fetchrow_array ){
#			my $cas9_prep = $self->_make_new_cas9_prep_from_db( \@fields, );
#		push @cas9_preps, $cas9_prep;
#	    }
#	}
#    } );
#    
#    return \@cas9_preps;
}

=method fetch_all_by_made_by

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_all_by_made_by( $crRNA );
  Purpose     : Fetch a cas9_prep given a crRNA object
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::crRNA object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_made_by {
    #my ( $self, $made_by, ) = @_;
}

=method fetch_all_by_prep_type

  Usage       : $cas9_preps = $cas9_prep_adaptor->fetch_all_by_prep_type( $crRNA );
  Purpose     : Fetch a cas9_prep given a crRNA object
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : Crispr::crRNA object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_prep_type {
    #my ( $self, $prep_type, ) = @_;
}

#_make_new_object_from_db
#
#Usage       : $cas9_prep = $self->_make_new_object_from_db( \@fields );
#Purpose     : Create a new object from a db entry
#Returns     : Crispr::DB::Cas9Prep object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    : 

sub _make_new_object_from_db {
    my ( $self, $fields ) = @_;
    return $self->_make_new_cas9_prep_from_db( $fields );
}

#_make_new_cas9_prep_from_db
#
#Usage       : $cas9_prep = $self->_make_new_cas9_prep_from_db( \@fields );
#Purpose     : Create a new Crispr::DB::Cas9Prep object from a db entry
#Returns     : Crispr::DB::Cas9Prep object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    : Expects fields to be in table order ie db_id, cas9_type, prep_type, made_by, date

sub _make_new_cas9_prep_from_db {
    my ( $self, $fields ) = @_;
    my $cas9_prep;
	
    my $cas9 = Crispr::Cas9->new( type => $fields->[1] );
	my %args = (
		db_id => $fields->[0],
        cas9 => $cas9,
		prep_type => $fields->[2],
		made_by => $fields->[3],
		date => $fields->[4],
	);
	
	$cas9_prep = Crispr::DB::Cas9Prep->new( %args );
    #$cas9_prep->cas9_prep_adaptor( $self );
	
    return $cas9_prep;
}

sub delete_cas9_prep_from_db {
	#my ( $self, $cas9_prep ) = @_;
	
	# first check cas9_prep exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if cas9_prep has talen pairs, delete tale and talen pairs

}


=method driver

  Usage       : $self->driver();
  Purpose     : Getter for the db driver.
  Returns     : Str
  Parameters  : None
  Throws      : If driver is not either mysql or sqlite
  Comments    : 

=cut

=method host

  Usage       : $self->host();
  Purpose     : Getter for the db host name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method port

  Usage       : $self->port();
  Purpose     : Getter for the db port.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbname

  Usage       : $self->dbname();
  Purpose     : Getter for the database (schema) name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method user

  Usage       : $self->user();
  Purpose     : Getter for the db user name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method pass

  Usage       : $self->pass();
  Purpose     : Getter for the db password.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbfile

  Usage       : $self->dbfile();
  Purpose     : Getter for the name of the SQLite database file.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method connection

  Usage       : $self->connection();
  Purpose     : Getter for the db Connection object.
  Returns     : DBIx::Connector
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method db_params

  Usage       : $self->db_params();
  Purpose     : method to return the db parameters as a HashRef.
                used internally to share the db params around Adaptor objects
  Returns     : HashRef
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method check_entry_exists_in_db

  Usage       : $self->check_entry_exists_in_db( $check_statement, $params );
  Purpose     : method used to check whether a particular entry exists in the database.
                Takes a MySQL statement of the form select count(*) from table where condition = ?;'
                and parameters
  Returns     : 1 if entry exists, undef if not
  Parameters  : check statement (Str)
                statement parameters (ArrayRef[Str])
  Throws      : 
  Comments    : 

=cut

=method fetch_rows_expecting_single_row

  Usage       : $self->fetch_rows_expecting_single_row( $sql_statement, $parameters );
  Purpose     : method to fetch a row from the database where the result should be unique.
  Returns     : ArrayRef
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
                If more than one row is returned.
  Comments    : 

=cut

=method fetch_rows_for_generic_select_statement

  Usage       : $self->fetch_rows_for_generic_select_statement( $sql_statement, $parameters );
  Purpose     : method to execute a generic select statement and return the rows from the db.
  Returns     : ArrayRef[Str]
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
  Comments    : 

=cut

=method _db_error_handling

  Usage       : $self->_db_error_handling( $error_message, $SQL_statement, $parameters );
  Purpose     : internal method to deal with error messages from the database.
  Returns     : Throws an exception that depends on the Adaptor type and
                the error message.
  Parameters  : Error Message (Str)
                MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : 
  Comments    : 

=cut

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod
 
=head1 SYNOPSIS
 
    use Crispr::DB::DBAdaptor;
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
    );
  
    my $cas9_prep_adaptor = $db_adaptor->get_adaptor( 'cas9_prep' );
    
    # store a cas9_prep object in the db
    $cas9_prep_adaptor->store( $cas9_prep );
    
    # retrieve a cas9_prep by id or name/requestor
    my $cas9_prep = $cas9_prep_adaptor->fetch_by_id( '214' );
  
    # retrieve a cas9_prep by combination of type and date
    my $cas9_prep = $cas9_prep_adaptor->fetch_by_type_and_date( 'cas9_dnls_native', '2015-04-27' );
    

=head1 DESCRIPTION
 
 A Cas9PrepAdaptor is an object used for storing and retrieving Cas9Prep objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
