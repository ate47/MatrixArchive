# MatrixArchive <!-- omit in toc -->

A Powershell tool to extract Messages/Files from Matrix rooms from a Matrix server without encoding and output it into Json files

**Table of content**

- [Archive](#archive)
	- [rooms.json file](#roomsjson-file)
	- [Archive command](#archive-command)

# Archive

## rooms.json file

To archive you need to create a [rooms.json](rooms.json) file with the format
 
```json
[
	{
		"rid" : "room id",
		"u"   : "room user id",
		"p"   : "room password"
	}
]
```

You can put as many room as you want in this array.

## Archive command

```Powershell
.\archive_room.ps1
```

The optional arguments are:
| Argument       | Default value                | Description                                                                                                                                                                        |
| -------------- | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ``RoomsFile``  | "room.json"                  | The room file, [see this](#roomsjson-file) for more information                                                                                                                    |
| ``Server``     | "https://matrix.example.com" | The matrix server to connect                                                                                                                                                       |
| ``DateFormat`` | "yyyy/MM/dd HH:mm:ss"        | Format for the date for each message in the json, [see this](https://docs.microsoft.com/en-us/dotnet/standard/base-types/custom-date-and-time-format-strings) for more information |

