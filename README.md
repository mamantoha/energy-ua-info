# energy-ua-info

**energy-ua-info** is a command-line tool written in Crystal that fetches and displays scheduled electricity outage information for Ukrainian cities. It retrieves data from the <https://energy-ua.info/> service and presents outage periods, durations, and next scheduled events for a specified city, group, and subgroup.

## Installation

1. **Install Crystal** (if not already installed):
   - See [Crystal installation guide](https://crystal-lang.org/install/)

2. **Clone the repository:**

   ```sh
   git clone https://github.com/mamantoha/energy-ua-info.git
   cd energy-ua-info
   ```

3. **Install dependencies:**

   ```sh
   shards install
   ```

4. **Build the executable:**
   ```sh
   shards build --release
   ```

## Usage

```
Використання: energy-ua-info CITY GROUP SUBGROUP

Де:
  CITY - назва міста (наприклад, kyiv, lviv, kharkiv)
  GROUP - номер групи (наприклад, 1, 2, 3)
  SUBGROUP - номер підгрупи (наприклад, 1, 2)

Приклад:
  energy-ua-info kyiv 1 1

Отримає інформацію про відключення електроенергії для Києва, групи 1, підгрупи 1.
    -h, --help                       Показати це повідомлення
```

**Example:**

```
energy-ua-info kharkiv 6 1
```

This will fetch and display the outage schedule for Kharkiv, group 6, subgroup 1.

## Output Example

## Contributing

1. Fork it (<https://github.com/mamantoha/energy-ua-info/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT

## Author

- [Anton Maminov](https://github.com/mamantoha) - creator and maintainer
