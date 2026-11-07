import Foundation

/// City and country names people actually type, mapped to IANA zones. The zone database
/// only knows "Asia/Kolkata" and "Asia/Shanghai"; nobody searches for those.
enum WorldClockPlaces {
    struct Place: Hashable { let city: String; let country: String; let zone: String }

    static let all: [Place] = [
        // Americas
        ("New York", "United States", "America/New_York"), ("Washington", "United States", "America/New_York"), ("Boston", "United States", "America/New_York"),
        ("Miami", "United States", "America/New_York"), ("Atlanta", "United States", "America/New_York"), ("Chicago", "United States", "America/Chicago"),
        ("Dallas", "United States", "America/Chicago"), ("Houston", "United States", "America/Chicago"), ("Austin", "United States", "America/Chicago"),
        ("Denver", "United States", "America/Denver"), ("Salt Lake City", "United States", "America/Denver"), ("Phoenix", "United States", "America/Phoenix"),
        ("Los Angeles", "United States", "America/Los_Angeles"), ("San Francisco", "United States", "America/Los_Angeles"), ("Seattle", "United States", "America/Los_Angeles"),
        ("San Diego", "United States", "America/Los_Angeles"), ("Las Vegas", "United States", "America/Los_Angeles"), ("Portland", "United States", "America/Los_Angeles"),
        ("Anchorage", "United States", "America/Anchorage"), ("Honolulu", "United States", "Pacific/Honolulu"),
        ("Toronto", "Canada", "America/Toronto"), ("Ottawa", "Canada", "America/Toronto"), ("Montreal", "Canada", "America/Toronto"),
        ("Vancouver", "Canada", "America/Vancouver"), ("Calgary", "Canada", "America/Edmonton"), ("Edmonton", "Canada", "America/Edmonton"),
        ("Winnipeg", "Canada", "America/Winnipeg"), ("Halifax", "Canada", "America/Halifax"), ("St. John's", "Canada", "America/St_Johns"),
        ("Mexico City", "Mexico", "America/Mexico_City"), ("Cancún", "Mexico", "America/Cancun"), ("Tijuana", "Mexico", "America/Tijuana"), ("Monterrey", "Mexico", "America/Monterrey"),
        ("Guatemala City", "Guatemala", "America/Guatemala"), ("San José", "Costa Rica", "America/Costa_Rica"), ("Panama City", "Panama", "America/Panama"),
        ("Havana", "Cuba", "America/Havana"), ("Kingston", "Jamaica", "America/Jamaica"), ("Santo Domingo", "Dominican Republic", "America/Santo_Domingo"), ("San Juan", "Puerto Rico", "America/Puerto_Rico"),
        ("Bogotá", "Colombia", "America/Bogota"), ("Medellín", "Colombia", "America/Bogota"), ("Caracas", "Venezuela", "America/Caracas"),
        ("Quito", "Ecuador", "America/Guayaquil"), ("Lima", "Peru", "America/Lima"), ("La Paz", "Bolivia", "America/La_Paz"),
        ("Santiago", "Chile", "America/Santiago"), ("Buenos Aires", "Argentina", "America/Argentina/Buenos_Aires"), ("Montevideo", "Uruguay", "America/Montevideo"),
        ("Asunción", "Paraguay", "America/Asuncion"), ("São Paulo", "Brazil", "America/Sao_Paulo"), ("Rio de Janeiro", "Brazil", "America/Sao_Paulo"),
        ("Brasília", "Brazil", "America/Sao_Paulo"), ("Manaus", "Brazil", "America/Manaus"), ("Recife", "Brazil", "America/Recife"),
        // Europe
        ("London", "United Kingdom", "Europe/London"), ("Manchester", "United Kingdom", "Europe/London"), ("Edinburgh", "United Kingdom", "Europe/London"),
        ("Dublin", "Ireland", "Europe/Dublin"), ("Lisbon", "Portugal", "Europe/Lisbon"), ("Porto", "Portugal", "Europe/Lisbon"),
        ("Madrid", "Spain", "Europe/Madrid"), ("Barcelona", "Spain", "Europe/Madrid"), ("Paris", "France", "Europe/Paris"), ("Lyon", "France", "Europe/Paris"),
        ("Brussels", "Belgium", "Europe/Brussels"), ("Amsterdam", "Netherlands", "Europe/Amsterdam"), ("Rotterdam", "Netherlands", "Europe/Amsterdam"),
        ("Luxembourg", "Luxembourg", "Europe/Luxembourg"), ("Berlin", "Germany", "Europe/Berlin"), ("Munich", "Germany", "Europe/Berlin"),
        ("Frankfurt", "Germany", "Europe/Berlin"), ("Hamburg", "Germany", "Europe/Berlin"), ("Zurich", "Switzerland", "Europe/Zurich"), ("Geneva", "Switzerland", "Europe/Zurich"),
        ("Vienna", "Austria", "Europe/Vienna"), ("Prague", "Czechia", "Europe/Prague"), ("Warsaw", "Poland", "Europe/Warsaw"), ("Kraków", "Poland", "Europe/Warsaw"),
        ("Budapest", "Hungary", "Europe/Budapest"), ("Bratislava", "Slovakia", "Europe/Bratislava"), ("Ljubljana", "Slovenia", "Europe/Ljubljana"), ("Zagreb", "Croatia", "Europe/Zagreb"),
        ("Belgrade", "Serbia", "Europe/Belgrade"), ("Sarajevo", "Bosnia and Herzegovina", "Europe/Sarajevo"), ("Rome", "Italy", "Europe/Rome"), ("Milan", "Italy", "Europe/Rome"),
        ("Venice", "Italy", "Europe/Rome"), ("Naples", "Italy", "Europe/Rome"), ("Malta", "Malta", "Europe/Malta"), ("Copenhagen", "Denmark", "Europe/Copenhagen"),
        ("Oslo", "Norway", "Europe/Oslo"), ("Stockholm", "Sweden", "Europe/Stockholm"), ("Gothenburg", "Sweden", "Europe/Stockholm"), ("Helsinki", "Finland", "Europe/Helsinki"),
        ("Tallinn", "Estonia", "Europe/Tallinn"), ("Riga", "Latvia", "Europe/Riga"), ("Vilnius", "Lithuania", "Europe/Vilnius"), ("Reykjavík", "Iceland", "Atlantic/Reykjavik"),
        ("Athens", "Greece", "Europe/Athens"), ("Sofia", "Bulgaria", "Europe/Sofia"), ("Bucharest", "Romania", "Europe/Bucharest"), ("Chișinău", "Moldova", "Europe/Chisinau"),
        ("Kyiv", "Ukraine", "Europe/Kyiv"), ("Minsk", "Belarus", "Europe/Minsk"), ("Moscow", "Russia", "Europe/Moscow"), ("Saint Petersburg", "Russia", "Europe/Moscow"),
        ("Kazan", "Russia", "Europe/Moscow"), ("Yekaterinburg", "Russia", "Asia/Yekaterinburg"), ("Novosibirsk", "Russia", "Asia/Novosibirsk"), ("Vladivostok", "Russia", "Asia/Vladivostok"),
        ("Istanbul", "Türkiye", "Europe/Istanbul"), ("Ankara", "Türkiye", "Europe/Istanbul"), ("Nicosia", "Cyprus", "Asia/Nicosia"), ("Tbilisi", "Georgia", "Asia/Tbilisi"),
        ("Yerevan", "Armenia", "Asia/Yerevan"), ("Baku", "Azerbaijan", "Asia/Baku"),
        // Middle East
        ("Riyadh", "Saudi Arabia", "Asia/Riyadh"), ("Jeddah", "Saudi Arabia", "Asia/Riyadh"), ("Mecca", "Saudi Arabia", "Asia/Riyadh"), ("Dammam", "Saudi Arabia", "Asia/Riyadh"),
        ("Dubai", "United Arab Emirates", "Asia/Dubai"), ("Abu Dhabi", "United Arab Emirates", "Asia/Dubai"), ("Sharjah", "United Arab Emirates", "Asia/Dubai"),
        ("Doha", "Qatar", "Asia/Qatar"), ("Manama", "Bahrain", "Asia/Bahrain"), ("Kuwait City", "Kuwait", "Asia/Kuwait"), ("Muscat", "Oman", "Asia/Muscat"),
        ("Sanaa", "Yemen", "Asia/Aden"), ("Amman", "Jordan", "Asia/Amman"), ("Beirut", "Lebanon", "Asia/Beirut"), ("Damascus", "Syria", "Asia/Damascus"),
        ("Baghdad", "Iraq", "Asia/Baghdad"), ("Tehran", "Iran", "Asia/Tehran"), ("Jerusalem", "Israel", "Asia/Jerusalem"), ("Tel Aviv", "Israel", "Asia/Jerusalem"),
        ("Gaza", "Palestine", "Asia/Gaza"), ("Ramallah", "Palestine", "Asia/Hebron"),
        // Africa
        ("Cairo", "Egypt", "Africa/Cairo"), ("Alexandria", "Egypt", "Africa/Cairo"), ("Khartoum", "Sudan", "Africa/Khartoum"), ("Addis Ababa", "Ethiopia", "Africa/Addis_Ababa"),
        ("Nairobi", "Kenya", "Africa/Nairobi"), ("Mombasa", "Kenya", "Africa/Nairobi"), ("Kampala", "Uganda", "Africa/Kampala"), ("Dar es Salaam", "Tanzania", "Africa/Dar_es_Salaam"),
        ("Kigali", "Rwanda", "Africa/Kigali"), ("Mogadishu", "Somalia", "Africa/Mogadishu"), ("Djibouti", "Djibouti", "Africa/Djibouti"),
        ("Lagos", "Nigeria", "Africa/Lagos"), ("Abuja", "Nigeria", "Africa/Lagos"), ("Accra", "Ghana", "Africa/Accra"), ("Abidjan", "Côte d'Ivoire", "Africa/Abidjan"),
        ("Dakar", "Senegal", "Africa/Dakar"), ("Bamako", "Mali", "Africa/Bamako"), ("Casablanca", "Morocco", "Africa/Casablanca"), ("Marrakesh", "Morocco", "Africa/Casablanca"),
        ("Algiers", "Algeria", "Africa/Algiers"), ("Tunis", "Tunisia", "Africa/Tunis"), ("Tripoli", "Libya", "Africa/Tripoli"), ("Kinshasa", "DR Congo", "Africa/Kinshasa"),
        ("Luanda", "Angola", "Africa/Luanda"), ("Lusaka", "Zambia", "Africa/Lusaka"), ("Harare", "Zimbabwe", "Africa/Harare"), ("Maputo", "Mozambique", "Africa/Maputo"),
        ("Johannesburg", "South Africa", "Africa/Johannesburg"), ("Cape Town", "South Africa", "Africa/Johannesburg"), ("Durban", "South Africa", "Africa/Johannesburg"),
        ("Windhoek", "Namibia", "Africa/Windhoek"), ("Gaborone", "Botswana", "Africa/Gaborone"), ("Antananarivo", "Madagascar", "Indian/Antananarivo"), ("Port Louis", "Mauritius", "Indian/Mauritius"),
        // South & Central Asia
        ("Delhi", "India", "Asia/Kolkata"), ("New Delhi", "India", "Asia/Kolkata"), ("Mumbai", "India", "Asia/Kolkata"), ("Bangalore", "India", "Asia/Kolkata"),
        ("Bengaluru", "India", "Asia/Kolkata"), ("Hyderabad", "India", "Asia/Kolkata"), ("Chennai", "India", "Asia/Kolkata"), ("Kolkata", "India", "Asia/Kolkata"),
        ("Pune", "India", "Asia/Kolkata"), ("Ahmedabad", "India", "Asia/Kolkata"), ("Jaipur", "India", "Asia/Kolkata"), ("Kochi", "India", "Asia/Kolkata"),
        ("Lucknow", "India", "Asia/Kolkata"), ("Chandigarh", "India", "Asia/Kolkata"), ("Goa", "India", "Asia/Kolkata"), ("Kerala", "India", "Asia/Kolkata"),
        ("Karachi", "Pakistan", "Asia/Karachi"), ("Lahore", "Pakistan", "Asia/Karachi"), ("Islamabad", "Pakistan", "Asia/Karachi"), ("Peshawar", "Pakistan", "Asia/Karachi"),
        ("Dhaka", "Bangladesh", "Asia/Dhaka"), ("Chittagong", "Bangladesh", "Asia/Dhaka"), ("Colombo", "Sri Lanka", "Asia/Colombo"), ("Kathmandu", "Nepal", "Asia/Kathmandu"),
        ("Thimphu", "Bhutan", "Asia/Thimphu"), ("Malé", "Maldives", "Indian/Maldives"), ("Kabul", "Afghanistan", "Asia/Kabul"),
        ("Tashkent", "Uzbekistan", "Asia/Tashkent"), ("Samarkand", "Uzbekistan", "Asia/Samarkand"), ("Almaty", "Kazakhstan", "Asia/Almaty"), ("Astana", "Kazakhstan", "Asia/Almaty"),
        ("Bishkek", "Kyrgyzstan", "Asia/Bishkek"), ("Dushanbe", "Tajikistan", "Asia/Dushanbe"), ("Ashgabat", "Turkmenistan", "Asia/Ashgabat"),
        // East & Southeast Asia
        ("Beijing", "China", "Asia/Shanghai"), ("Shanghai", "China", "Asia/Shanghai"), ("Shenzhen", "China", "Asia/Shanghai"), ("Guangzhou", "China", "Asia/Shanghai"),
        ("Chengdu", "China", "Asia/Shanghai"), ("Hangzhou", "China", "Asia/Shanghai"), ("Wuhan", "China", "Asia/Shanghai"), ("Xi'an", "China", "Asia/Shanghai"),
        ("Ürümqi", "China", "Asia/Urumqi"), ("Hong Kong", "Hong Kong", "Asia/Hong_Kong"), ("Macau", "Macau", "Asia/Macau"), ("Taipei", "Taiwan", "Asia/Taipei"),
        ("Tokyo", "Japan", "Asia/Tokyo"), ("Osaka", "Japan", "Asia/Tokyo"), ("Kyoto", "Japan", "Asia/Tokyo"), ("Sapporo", "Japan", "Asia/Tokyo"),
        ("Seoul", "South Korea", "Asia/Seoul"), ("Busan", "South Korea", "Asia/Seoul"), ("Pyongyang", "North Korea", "Asia/Pyongyang"),
        ("Ulaanbaatar", "Mongolia", "Asia/Ulaanbaatar"), ("Hanoi", "Vietnam", "Asia/Ho_Chi_Minh"), ("Ho Chi Minh City", "Vietnam", "Asia/Ho_Chi_Minh"), ("Saigon", "Vietnam", "Asia/Ho_Chi_Minh"),
        ("Bangkok", "Thailand", "Asia/Bangkok"), ("Chiang Mai", "Thailand", "Asia/Bangkok"), ("Phuket", "Thailand", "Asia/Bangkok"), ("Vientiane", "Laos", "Asia/Vientiane"),
        ("Phnom Penh", "Cambodia", "Asia/Phnom_Penh"), ("Yangon", "Myanmar", "Asia/Yangon"), ("Kuala Lumpur", "Malaysia", "Asia/Kuala_Lumpur"), ("Penang", "Malaysia", "Asia/Kuala_Lumpur"),
        ("Singapore", "Singapore", "Asia/Singapore"), ("Jakarta", "Indonesia", "Asia/Jakarta"), ("Bali", "Indonesia", "Asia/Makassar"), ("Denpasar", "Indonesia", "Asia/Makassar"),
        ("Surabaya", "Indonesia", "Asia/Jakarta"), ("Manila", "Philippines", "Asia/Manila"), ("Cebu", "Philippines", "Asia/Manila"), ("Bandar Seri Begawan", "Brunei", "Asia/Brunei"),
        ("Dili", "Timor-Leste", "Asia/Dili"),
        // Oceania
        ("Sydney", "Australia", "Australia/Sydney"), ("Canberra", "Australia", "Australia/Sydney"), ("Melbourne", "Australia", "Australia/Melbourne"), ("Brisbane", "Australia", "Australia/Brisbane"),
        ("Gold Coast", "Australia", "Australia/Brisbane"), ("Perth", "Australia", "Australia/Perth"), ("Adelaide", "Australia", "Australia/Adelaide"), ("Darwin", "Australia", "Australia/Darwin"),
        ("Hobart", "Australia", "Australia/Hobart"), ("Auckland", "New Zealand", "Pacific/Auckland"), ("Wellington", "New Zealand", "Pacific/Auckland"), ("Christchurch", "New Zealand", "Pacific/Auckland"),
        ("Port Moresby", "Papua New Guinea", "Pacific/Port_Moresby"), ("Suva", "Fiji", "Pacific/Fiji"), ("Nouméa", "New Caledonia", "Pacific/Noumea"), ("Guam", "Guam", "Pacific/Guam"),
        ("Apia", "Samoa", "Pacific/Apia"), ("Papeete", "French Polynesia", "Pacific/Tahiti"), ("Tahiti", "French Polynesia", "Pacific/Tahiti"),
        // Reference
        ("UTC", "Coordinated Universal Time", "UTC"), ("GMT", "Greenwich Mean Time", "GMT"),
    ].map { Place(city: $0.0, country: $0.1, zone: $0.2) }

    /// Alternate spellings and old names people still type.
    static let synonyms: [String: String] = [
        "bombay": "Mumbai", "calcutta": "Kolkata", "madras": "Chennai", "peking": "Beijing", "canton": "Guangzhou",
        "kiev": "Kyiv", "st petersburg": "Saint Petersburg", "st. petersburg": "Saint Petersburg", "constantinople": "Istanbul",
        "rangoon": "Yangon", "bombai": "Mumbai", "ny": "New York", "nyc": "New York", "la": "Los Angeles", "sf": "San Francisco",
        "uae": "Dubai", "usa": "New York", "us": "New York", "uk": "London", "ksa": "Riyadh", "hk": "Hong Kong", "sg": "Singapore",
        "england": "London", "scotland": "Edinburgh", "britain": "London", "holland": "Amsterdam", "turkey": "Istanbul", "burma": "Yangon",
        "czech republic": "Prague", "korea": "Seoul", "america": "New York", "emirates": "Dubai", "saudi": "Riyadh", "ivory coast": "Abidjan",
    ]

    struct Hit: Hashable, Identifiable {
        let city: String; let country: String; let zone: String
        var id: String { city + "|" + zone }
        /// Label to store when the searched city is not the zone's own name (Delhi → Asia/Kolkata).
        var label: String? { WorldClockZone.cityName(zone) == city ? nil : city }
    }

    static func search(_ raw: String) -> [Hit] {
        let q = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let fold: (String) -> String = { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() }
        let needle = fold(synonyms[q] ?? q)
        var hits: [(Hit, Int)] = []
        for p in all {
            let city = fold(p.city), country = fold(p.country)
            let score: Int
            if city == needle { score = 0 }
            else if city.hasPrefix(needle) { score = 1 }
            else if country == needle { score = 2 }
            else if country.hasPrefix(needle) { score = 3 }
            else if city.contains(needle) { score = 4 }
            else if country.contains(needle) { score = 5 }
            else { continue }
            hits.append((Hit(city: p.city, country: p.country, zone: p.zone), score))
        }
        // Raw identifiers and abbreviations ("Asia/Kolkata", "GMT+5:30", "CET") still work.
        if hits.count < 6 {
            let idNeedle = needle.replacingOccurrences(of: " ", with: "_")
            for id in WorldClockStore.allIdentifiers where fold(id).contains(idNeedle) || (TimeZone(identifier: id)?.abbreviation()?.lowercased() == needle) {
                if !hits.contains(where: { $0.0.zone == id }) {
                    hits.append((Hit(city: WorldClockZone.cityName(id), country: id.split(separator: "/").first.map(String.init) ?? "", zone: id), 6))
                }
            }
        }
        var seen = Set<String>()
        return hits.sorted { $0.1 < $1.1 || ($0.1 == $1.1 && $0.0.city < $1.0.city) }
            .compactMap { seen.insert($0.0.city + $0.0.zone).inserted ? $0.0 : nil }
            .prefix(10).map { $0 }
    }
}
