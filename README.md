# ChatGPT - Fhem
## ChatGPT - Fhem Integration

**39_ChatGPT.pm**

Dieses Fhem Modul stellt eine Verbindung zur OpenAI API zur Verfügung. 

**update**

`update add https://raw.githubusercontent.com/RP-Develop/ChatGPT/main/controls_ChatGPT.txt`

### Voraussetzung:
Ein kostenpflichtiger API-Key ist dafür notwendig. Zu Erstellen über die Profileinstellung deines OpenAI Accounts [OpenAI](https://platform.openai.com)

### Fhem  - 39_ChatGPT.pm
`define <name> ChatGPT <API-Key>`

API-Key wird in DEF verschlüsselt angezeigt.

`set <name> Request <txt>`

Texteingabe.

`get <name> Response`

Zeigt JSON Antwort an.

`get <name> Header`

Zeigt Header an.

`get <name> apiKey`

Zeigt API-Key an (entschlüsselt).

### Quellen
