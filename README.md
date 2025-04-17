# Description:
This script selects the best Wireguard AirVPN server located in a specific country 
(default: Netherlands) by evaluating server load and avoiding exit nodes 
from the Tor network. Optionally, it also checks each IP with 
IPQualityScore to further ensure it's not flagged as Tor or malicious.

Once a valid server is selected, it sets the SERVER_NAMES environment 
variable with the corresponding AirVPN hostname (e.g., "Zubeneschamali").

# Features:
- Sorts servers by load score (bandwidth usage + current load)
- Skips servers flagged as Tor exit nodes
- (Optional) Skips servers flagged by IPQualityScore
- Exports the selected server's hostname to SERVER_NAMES

# Configuration:
- COUNTRY: Target country for server selection
- AIRVPN_API_KEY: Your AirVPN API token
- IPQS_API_KEY: Your IPQualityScore API token
- USE_IPQS_CHECK: Set to "true" to enable IPQualityScore validation

# Usage:
download the scirpt (es. in /usr/local/bin/)  
in gluetun compose add in volume section  
volumes:    
      - /usr/local/bin/pick_best_airvpn.sh:/pick_best_airvpn.sh:ro      

and override the entry point:    
entrypoint: /bin/sh -c "/pick_best_airvpn.sh"
