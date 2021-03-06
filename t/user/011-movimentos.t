

use strict;
use warnings;

use Test::More;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Catalyst::Test q(RNSP::PCS);

use HTTP::Request::Common;
use Package::Stash;

use RNSP::PCS::TestOnly::Mock::AuthUser;

my $schema = RNSP::PCS->model('DB');
my $stash  = Package::Stash->new('Catalyst::Plugin::Authentication');
my $user   = RNSP::PCS::TestOnly::Mock::AuthUser->new;

$RNSP::PCS::TestOnly::Mock::AuthUser::_id    = 1;
@RNSP::PCS::TestOnly::Mock::AuthUser::_roles = qw/ admin /;

$stash->add_symbol( '&user',  sub { return $user } );
$stash->add_symbol( '&_user', sub { return $user } );


eval {
  $schema->txn_do(
    sub {
        my $city = $schema->resultset('City')->create(
                {
                    uf   => 'SP',
                    name => 'Pederneiras'
                },
        );

        my $city2 = $schema->resultset('City')->create(
            {
                uf   => 'XX',
                name => 'AWS'
            },
        );

      my ( $res, $c ) = ctx_request(
        POST '/api/user',
        [
          api_key                        => 'test',
          'user.create.name'             => 'Foo Bar',
          'user.create.email'            => 'foo@email.com',
          'user.create.password'         => 'foobarquux1',
          'user.create.password_confirm' => 'foobarquux1',
          'user.create.city_id'          => $city->id,
          'user.create.movimento'         => 1
        ]
      );
      ok( $res->is_success, 'user created' );
      is( $res->code, 201, 'user created' );
      ok(
        my $new_user =
          $schema->resultset('User')->find( { email => 'foo@email.com' } ),
        'user in DB'
      );
      is(eval{$new_user->movimento->user_id}, $new_user->id, 'criado como movimento');



      ( $res, $c ) = ctx_request(
        POST '/api/user',
        [
          api_key                        => 'test',
          'user.create.name'             => 'Foo XX',
          'user.create.email'            => 'errorme@email.com',
          'user.create.password'         => 'foobarquux1',
          'user.create.password_confirm' => 'foobarquux1',
          'user.create.city_id'          => $city->id,
          'user.create.movimento'         => 1
        ]
      );

      ok( !$res->is_success, 'user not created' );
      is( $res->code, 400, 'user not created' );
      like($res->content, qr|user.create.movimento.invalid|, 'error na cidade ja tem movimento');

      ( $res, $c ) = ctx_request(
        POST '/api/user',
        [
          api_key                        => 'test',
          'user.create.name'             => 'Foo XX',
          'user.create.email'            => 'noterro@email.com',
          'user.create.password'         => 'foobarquux1',
          'user.create.password_confirm' => 'foobarquux1',
          'user.create.city_id'          => $city->id
        ]
      );
      ok( $res->is_success, 'user created na city 1 como normal' );
      is( $res->code, 201, 'user created na city 1 como normal' );

      ( $res, $c ) = ctx_request(
        POST '/api/user',
        [
          api_key                        => 'test',
          'user.create.name'             => 'Foo XX',
          'user.create.email'            => 'errorme@email.com',
          'user.create.password'         => 'foobarquux1',
          'user.create.password_confirm' => 'foobarquux1',
          'user.create.city_id'          => $city2->id,
          'user.create.movimento'         => 1
        ]
      );
      ok( $res->is_success, 'user created na city 2 como movimento' );
      is( $res->code, 201, 'user created na city 2 como movimento' );

      use JSON qw(encode_json);

      # update user
      ( $res, $c ) = ctx_request(
        POST '/api/user/' . $new_user->id,
        [
          api_key                        => 'test',
          'user.update.name'             => 'Foo Bar',
          'user.update.email'            => 'bar@email.com',
          'user.update.movimento'         => 0,

        ]
      );
      ok( $res->is_success, 'user updated perdeu a prefeitura' );
      is( $res->code, 202, 'user updated -- 202 Accepted' );


      ( $res, $c ) = ctx_request(
        POST '/api/user',
        [
          api_key                        => 'test',
          'user.create.name'             => 'Foo XX',
          'user.create.email'            => 'orme@email.com',
          'user.create.password'         => 'foobarquux1',
          'user.create.password_confirm' => 'foobarquux1',
          'user.create.city_id'          => $city->id,
          'user.create.movimento'         => 1
        ]
      );
      ok( $res->is_success, 'user created to city 1 again' );
      is( $res->code, 201, 'user created to city 1 again' );

      ok(
        my $changecity =
          $schema->resultset('User')->find( { email => 'errorme@email.com' } ),
        'user in DB'
      );
      is(eval{$new_user->movimento->user_id}, $new_user->id, 'criado como movimento');

      ( $res, $c ) = ctx_request(
        POST '/api/user/' . $changecity->id,
        [
          api_key                        => 'test',
          'user.update.name'             => 'Foo Bar',
          'user.update.email'            => 'errorme@email.com',
          'user.update.city_id'          => $city2->id,

        ]
      );

      ok( $res->is_success, 'user updated e perdeu a prefeitura' );
      is( $res->code, 202, 'user updated -- 202 Accepted' );


      die 'rollback';
    }
  );

};

die $@ unless $@ =~ /rollback/;

done_testing;
