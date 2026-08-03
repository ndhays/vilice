# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # A pasted AppConfig may carry secret *values* on its way to the box. It rides
  # stdin so it never reaches the recorded command line or the box's chain — but it
  # does arrive here as a form parameter, and an unfiltered one would be written to
  # the Rails log in the clear, which is the one place nobody thinks to look.
  :config
]
