#!/usr/bin/env ruby
$: << File.dirname(__FILE__) + '/../..'
require 'wukong'
require 'wukong/and_pig' ; include Wukong::AndPig

HDFS_BASE_DIR = 'meta/lang'
Wukong::AndPig::PigVar.working_dir = HDFS_BASE_DIR


#
# Load basic types
#


class Token < Struct.new(:rsrc, :context, :user_id, :token, :usages)
end

:tokens_users_0 << Token.pig_load('meta/datanerds/token_count/tokens')
:tokens_users   << :tokens_users_0.generate(:user_id, :token, :usages)
:tokens_users.checkpoint!

pig_comment %Q{
# ***************************************************************************
#
# Global totals
#
# Each row in Tokens lists a (user, token, usages)
# We want
#   Sum of all usage counts = total tokens seen in tweet stream.
#   Number of distinct tokens
#   Number of distinct users <- different than total in twitter_users.tsv
#                               because we want only users that say stuff.
}

def count_distinct relation, field, options={}
  result_name = options[:as] || "#{relation.name}_#{field}_count".to_sym
  a = relation.
    generate(field).set!.
    distinct(options).set!.
    group(:all).set!
  result_name << a.generate(["COUNT(#{a.relation})", :u_count]).set!
end

pig_comment "Count Users"
tok_users_count = count_distinct(:tokens_users, :user_id).checkpoint!

pig_comment "Count Tokens"
tok_tokens_count = count_distinct(:tokens_users, :token, :parallel => 10).checkpoint!


pig_comment %Q{
# ***************************************************************************
#
# Statistics for each user
}
def user_stats users_tokens
  users_tokens.group(:by => :user_id).set!.
    generate(
      [:group, :user_id],
      ["(int)COUNT(#{users_tokens.relation})",      :tot_tokens],
      ["(int)SUM(#{users_tokens.relation}.usages)", :tot_usages],
      ["FLATTEN(TwTokenUsers.(token, usages) )", "(token, usages)"]
    ).set!.
    generate(:user_id, :token, :usages,
         ["(float)(1.0*usages / tot_usages)", :usage_pct],
         ["(float)(1.0*usages / tot_usages) * (1.0*(float)usages / tot_usages)", :usage_pct_sq]
    ).set!
end

user_stats(:tokens_users).checkpoint!

# tokens_users_0 = Token.pig_load('meta/datanerds/token_count/tokens')
# tokens_users   = tokens_users_0.generate(:user_id, :token, :usages)
# tokens_users.store!