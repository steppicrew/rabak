use strict;
use Test;

BEGIN { plan tests => 63 };

use RabakLib::Conf;
use Data::Dumper;
use FindBin qw($Bin);

print "# Testing 'RabakLib::Conf'\n";

# modify bin directory for including
$Bin.= "/../..";

# creating root conf
my $oRootConf= RabakLib::Conf->new('testconfig');
ok ref $oRootConf, 'RabakLib::Conf', 'Creating RootConf';
ok $oRootConf->{NAME}, 'testconfig', 'Name of RootConf 1';
ok $oRootConf->get_value('name'), 'testconfig', 'Name of RootConf 2';
ok $oRootConf->get_full_name(), '', 'Full name of RootConf';

# creating test value
$oRootConf->set_value('test_key', 'test_value');
ok $oRootConf->get_value('test_key'), 'test_value', 'Setting scalar value (RootConf)';
ok $oRootConf->get_node('test_key'), undef, 'Getting scalar value as node (RootConf)';

# checking case insensivity
$oRootConf->set_value('tesT_Key', 'root test value');
ok $oRootConf->get_value('tesT_Key'), 'root test value', 'Setting scalar value (upper case 1)';
ok $oRootConf->get_value('test_key'), 'root test value', 'Setting scalar value (upper case 2)';

# creating 1st level sub config
my $oSubConf1= RabakLib::Conf->new('subconf1', $oRootConf);
$oRootConf->set_value('subconf1', $oSubConf1);
ok $oSubConf1->{PARENT_CONF}, $oRootConf, 'Reference to RootConf from SubConf1';
ok $oRootConf->get_value('subconf1'), undef, 'Getting reference as value';
ok $oSubConf1, $oRootConf->get_node('subconf1'), 'Reference to SubConf1 from RootConf';
ok $oSubConf1, $oSubConf1->get_node('subconf1'), 'Reference to SubConf1 from SubConf1';
ok $oSubConf1->get_value('name'), 'subconf1', 'Name of SubConf1';
ok $oSubConf1->get_full_name(), 'subconf1', 'Full name of SubConf1';

$oSubConf1->set_value('test_key', 'sub1 test value');
ok $oSubConf1->get_value('test_key'), 'sub1 test value', 'Setting scalar value (SubConf1)';

# creating 2nd level sub config
my $oSubConf11= RabakLib::Conf->new('subconf11', $oSubConf1);
$oSubConf1->set_value('subconf11', $oSubConf11);
ok $oSubConf11->{PARENT_CONF}, $oSubConf1, 'Reference to SubConf1 from SubConf11';
ok $oSubConf1->get_value('subconf11'), undef, 'Getting reference as value';
ok $oSubConf11, $oSubConf1->get_node('subconf11'), 'Reference to SubConf11 from SubConf1';
ok $oSubConf11, $oSubConf11->get_node('subconf11'), 'Reference to SubConf11 from SubConf11';
ok $oSubConf11->get_value('name'), 'subconf11', 'Name of SubConf11';
ok $oSubConf11->get_full_name(), 'subconf1.subconf11', 'Full name of SubConf11';

# test various access types for same named properties
$oSubConf11->set_value('test_key', 'sub11 test value');
ok $oSubConf11->get_value('test_key'), 'sub11 test value', 'Setting scalar value (SubConf11)';
ok $oSubConf11->get_value('.test_key'), 'sub1 test value', 'Getting inherited scalar value (SubConf11) 1';
ok $oSubConf11->get_value('..test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 2';
ok $oSubConf11->get_value('...test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 3';
ok $oSubConf11->get_value('/test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 4';
ok $oSubConf11->get_value('/.test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 5';
ok $oSubConf11->get_value('./test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 6';
ok $oSubConf11->get_value('./.test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 7';
ok $oSubConf11->get_value('/./.test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 8';
ok $oSubConf11->get_value('//test_key'), 'root test value', 'Getting inherited scalar value (SubConf11) 9';

# test various setting types for same named properties
$oSubConf11->set_value('.test_key', 'sub1 test value 1');
ok $oSubConf11->get_value('.test_key'), 'sub1 test value 1', 'Setting parental scalar value (SubConf11) 1';
ok $oSubConf1->get_value('test_key'), 'sub1 test value 1', 'Setting scalar value (SubConf11) 1';

$oSubConf11->set_value('....test_key', 'root test value 1');
ok $oSubConf11->get_value('/test_key'), 'root test value 1', 'Setting parental scalar value (SubConf11) 1';
ok $oSubConf1->get_value('/test_key'), 'root test value 1', 'Setting scalar value (SubConf11) 1';
ok $oRootConf->get_value('.test_key'), 'root test value 1', 'Setting scalar value (SubConf11) 1';
ok $oRootConf->get_value('/test_key'), 'root test value 1', 'Setting scalar value (SubConf11) 1';
ok $oRootConf->get_value('test_key'), 'root test value 1', 'Setting scalar value (SubConf11) 1';

$oSubConf11->set_value('/test_key', 'root test value 2');
ok $oSubConf11->get_value('/test_key'), 'root test value 2', 'Setting parental scalar value (SubConf11)';
ok $oSubConf1->get_value('/test_key'), 'root test value 2', 'Setting scalar value (SubConf1)';
ok $oRootConf->get_value('.test_key'), 'root test value 2', 'Setting scalar value (RootConf)';
ok $oRootConf->get_value('/test_key'), 'root test value 2', 'Setting scalar value (RootConf)';
ok $oRootConf->get_value('test_key'), 'root test value 2', 'Setting scalar value (RootConf)';
ok $oSubConf1->get_value('test_key'), 'sub1 test value 1', 'Checking other sub values';
ok $oSubConf11->get_value('test_key'), 'sub11 test value', 'Checking other sub values';

# test cloning
my $oCloneSubConf1= RabakLib::Conf->CloneConf($oSubConf1);
ok $oCloneSubConf1->{PARENT_CONF}, $oRootConf, 'Reference to RootConf from CloneSubConf1';
ok $oCloneSubConf1, $oRootConf->get_node('subconf1'), 'Reference to CloneSubConf1 from RootConf';
ok $oSubConf11->{PARENT_CONF}, $oCloneSubConf1, 'Reference to CloneSubConf1 from SubConf11';
ok $oSubConf11, $oCloneSubConf1->get_node('subconf11'), 'Reference to SubConf11 from CloneSubConf1';
ok $oCloneSubConf1->get_value('test_key'), 'sub1 test value 1', 'Getting scalar value of CloneSubConf';
ok $oSubConf11->get_value('.test_key'), 'sub1 test value 1', 'Getting inherited scalar value of CloneSubConf (SubConf11)';
ok $oSubConf11->get_value('/test_key'), 'root test value 2', 'Getting inherited scalar value of RootConf (SubConf11)';
ok $oSubConf11->get_value('subconf1.subconf11.test_key'), 'sub11 test value', 'Getting scalar value of SubConf11 via Full Path';
ok $oRootConf->get_value('subconf1.subconf11.test_key'), 'sub11 test value', 'Getting scalar value of SubConf11 from RootConf';
ok $oRootConf->get_node('subconf1.subconf11'), $oSubConf11, 'Getting node SubConf11 from RootConf';

# test switch setting
ok $oSubConf11->get_switch('test_key'), 'sub11 test value', 'Getting switch from SubConf11';
ok $oRootConf->get_switch('test_key'), 'root test value 2', 'Getting switch from RootConf';
$oRootConf->set_value('switch.test_key', 'test switch');
$oSubConf11->set_value('switch.test_key', 'test switch sub11');
ok $oSubConf11->get_switch('test_key'), 'test switch', 'Getting switch from SubConf11';
ok $oRootConf->get_switch('test_key'), 'test switch', 'Getting switch from RootConf';

# test set_values and resolveObjects() with recursion check and wrong reference
my $oSubConf2= RabakLib::Conf->new('subconf2', $oRootConf);
$oRootConf->set_value('subconf2', $oSubConf2);
$oSubConf11->set_values({
    '/test_key' => '&subconf2 &subconf1 str\ ing',
    '.test_key' => 'sub1',
    '.reference' => '&/test_key &test_key &subconf11.test_key &/subconf11.test_key',
    'test_key' => 'sub11 &test_key',
});
ok $oRootConf->get_value('test_key'), '&subconf2 &subconf1 str ing', 'Setting multiple values (1)';
ok $oCloneSubConf1->get_value('test_key'), 'sub1', 'Setting multiple values (2)';
ok $oCloneSubConf1->get_value('reference'), '&/test_key &test_key &subconf11.test_key &/subconf11.test_key', 'Setting multiple values (3)';
my @oResolvedObjects= $oSubConf11->resolveObjects('reference');
my @oExpected= ($oSubConf2, $oCloneSubConf1, 'str ing', 'sub1', 'sub11');
ok join("][", @oResolvedObjects), join("][", @oExpected), 'Resolving Objects with recursion and nonexisting reference';

