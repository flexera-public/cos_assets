name 'VM Information for Azure and Azure Resource Manager'
rs_ca_ver 20160622
short_description "![RS Policy](https://goo.gl/RAcMcU =64x64)\n
This automated policy CAT will pull public and private ip's via RightScale CM for os information for Azure and Azure Resource Manager."

#Copyright 2017 RightScale
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

#RightScale Cloud Application Template (CAT)

# DESCRIPTION
# Find public and private ip's, os information for Azure and Azure Resource Manager.
#
# FEATURES
# 
#

##################
# User inputs    #
##################
parameter "param_customer_name" do
  category "Customer_Name"
  label "Customer_Name"
  type "string"
  description "Enter Customer Name"
end

parameter "param_email" do
  category "Contact"
  label "Email addresses"
  description "Enter RS email address" # email address associated with RS user"
  type "string"
end

parameter "param_password" do
  category "Password"
  label "Password"
  description "Enter RS Password"
  type "string"
end

parameter "param_rs_endpoint" do
  category "Endpoint"
  label "RightScale Endpoints"
  description "Enter RS API endpoint (us-3.rightscale.com -or- us-4.rightscale.com)" # us-3.rightscale.com -or- us-4.rightscale.com"
  allowed_values "us-3.rightscale.com", "us-4.rightscale.com"
  default "us-4.rightscale.com"
  type "string"
end

parameter "param_accounts" do
  category "Accounts"
  label "RightScale Accounts"
  description "Enter comma seperated list of RS Account Number(s) or the Parent Account number. Example: 1234,4321,1111"
  type "string"
end

operation "launch" do
  description "Create VM spareadsheet"
  definition "launch"
end

define launch($param_customer_name, $param_email, $param_password, $param_rs_endpoint,$param_accounts) do
end


define handle_error() do
  #error_msg has the response from the api , use that as the error in the email.
  #$$error_msg = $_error["message"]
  $$error_msg = " failed to delete"
  $_error_behavior = "skip"
end

# Returns the RightScale account number in which the CAT was launched.
define find_account_name() return $account_name do
  $session_info = rs_cm.sessions.get(view: "whoami")
  $acct_link = select($session_info[0]["links"], {rel: "account"})
  $acct_href = $acct_link[0]["href"]
  $account_name = rs_cm.get(href: $acct_href).name
end