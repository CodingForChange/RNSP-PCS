
package RNSP::PCS::Schema::ResultSet::Variable;

use namespace::autoclean;

use Moose;
extends 'DBIx::Class::ResultSet';
with 'RNSP::PCS::Role::Verification';
with 'RNSP::PCS::Schema::Role::InflateAsHashRef';

use Data::Verifier;
use JSON qw /encode_json/;
use String::Random;
use MooseX::Types::Email qw/EmailAddress/;

use RNSP::PCS::Types qw /VariableType/;

sub _build_verifier_scope_name { 'variable' }

sub verifiers_specs {
    my $self = shift;
    return {
        create => Data::Verifier->new(
            profile => {
                name        => { required => 1, type => 'Str' },
                explanation => { required => 1, type => 'Str' },
                cognomen    => {
                    required   => 1,
                    type       => 'Str',
                    post_check => sub {
                        my $r = shift;
                        return $r->get_value('cognomen') =~ /^[A-Z](?:[A-Z0-9_])+$/i;
                      }
                },
                type             => { required => 1, type => VariableType },
                user_id          => { required => 1, type => 'Int' },
                source           => { required => 0, type => 'Str' },
                period           => { required => 0, type => 'Str' },
                measurement_unit => { required => 0, type => 'Str' },
                is_basic         => { required => 0, type => 'Bool' },
            },
        ),

        update => Data::Verifier->new(
            profile => {
                id          => { required => 1, type => 'Int' },
                name        => { required => 0, type => 'Str' },
                explanation => { required => 0, type => 'Str' },
                cognomen    => {
                    required   => 0,
                    type       => 'Str',
                    post_check => sub {
                        my $r = shift;
                        return $r->get_value('cognomen') =~ /^[A-Z](?:[A-Z0-9_])+$/i;
                      }
                },
                type             => { required => 0, type => VariableType },
                source           => { required => 0, type => 'Str' },
                period           => { required => 1, type => 'Str' },
                measurement_unit => { required => 0, type => 'Str' },
                is_basic         => { required => 0, type => 'Bool' },

            },
        ),

    };
}

sub action_specs {
    my $self = shift;
    return {
        create => sub {
            my %values = shift->valid_values;
            do { delete $values{$_} unless defined $values{$_} }
              for keys %values;
            return unless keys %values;

            my $var = $self->create( \%values );

            $var->discard_changes;
            return $var;
        },
        update => sub {
            my %values = shift->valid_values;

            do { delete $values{$_} unless defined $values{$_} }
              for keys %values;
            return unless keys %values;

            my $var = $self->find( delete $values{id} )->update( \%values );
            $var->discard_changes;
            return $var;
        },

    };
}

1;

