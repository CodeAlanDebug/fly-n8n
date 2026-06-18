# Shared setup for all bats suites. Sourcing the aggregator makes every helper
# function from scripts/lib/*.sh available. Each suite loads this in setup():
#
#     setup() { load 'test_helper'; }
#
source "${BATS_TEST_DIRNAME}/../scripts/version-detection.sh"
