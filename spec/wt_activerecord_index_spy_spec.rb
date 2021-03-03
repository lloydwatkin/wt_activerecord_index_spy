# frozen_string_literal: true

require "tempfile"

RSpec.describe WtActiverecordIndexSpy do
  it "has a version number" do
    expect(WtActiverecordIndexSpy::VERSION).not_to be nil
  end

  describe ".watch_queries" do
    around(:each) do |example|
      @aggregator = WtActiverecordIndexSpy::Aggregator.new
      described_class.watch_queries(aggregator: @aggregator) do
        example.run
      end
    end

    context "when a query does not use an index" do
      it "adds the query to the certain list" do
        User.find_by(name: "lala")

        expect(@aggregator.results.certains.first.query)
          .to include("WHERE `users`.`name` = 'lala'")
      end
    end

    context "when a query uses the primary key index" do
      it "does not add the query to result aggregator" do
        User.find_by(id: 1)

        expect(@aggregator.results.certains).to be_empty
        expect(@aggregator.results.uncertains).to be_empty
      end
    end

    context "when a query uses some index" do
      it "does not add the query to result aggregator" do
        User.find_by(email: "aa@aa.com")

        expect(@aggregator.results.certains).to be_empty
        expect(@aggregator.results.uncertains).to be_empty
      end
    end

    context "when a query filter multiple fields with no index" do
      it "adds the query to the certain list" do
        User.create(name: "lala", age: 20)
        User.create(name: "lala2", age: 10)

        User.find_by(age: 20, name: "popo")

        expect(@aggregator.results.certains.first.query)
          .to include("WHERE `users`.`age` = 20")
      end
    end

    context "when EXPLAIN returns 'Impossible WHERE noticed after reading const tables'" do
      it "does not add the query to result aggregator" do
        User.create(name: "lala", age: 20)

        User.where(id: 1, email: "aa@aa.com", age: 20).to_a

        expect(@aggregator.results.certains).to be_empty
        expect(@aggregator.results.uncertains).to be_empty
      end
    end

    context "when there is an index but the query returns all records" do
      it "does not add the query to result aggregator" do
        User.create!(name: "Lala1", city_id: 1)
        User.create!(name: "Lala2", city_id: 1)
        User.create!(name: "Lala3", city_id: 1)

        User.where(city_id: 1).to_a

        expect(@aggregator.results.certains).to be_empty
        expect(@aggregator.results.uncertains).to be_empty
      end
    end

    context "when a query has index but a subquery does not" do
      it "adds the query to the certain list" do
        City.create!(name: "Rio", id: 1)
        City.create!(name: "Santo Andre", id: 2)
        City.create!(name: "Maua", id: 3)

        User.create!(name: "Lala1", city_id: 1)
        User.create!(name: "Lala2", city_id: 2)
        User.create!(name: "Lala3", city_id: 1)

        cities = City.where(name: "Santo Andre")
        User.where(city_id: cities).to_a

        expect(@aggregator.results.certains.count).to eq(0)
        expect(@aggregator.results.uncertains.first.identifier).to eq("User Load")
        expect(@aggregator.results.uncertains.first.query)
          .to include("WHERE `users`.`city_id` IN")
      end
    end

    context "when ignore_queries_originated_in_test_code=true" do
      around do |example|
        described_class.ignore_queries_originated_in_test_code = true
        example.run
        described_class.ignore_queries_originated_in_test_code = false
      end

      it "ignores queries originated in test code" do
        User.create(name: "lala")
        User.find_by(name: "any")

        expect(@aggregator.results.certains.count).to eq(0)
        expect(@aggregator.results.uncertains.count).to eq(0)
      end

      it "does not ignore queries originated outside tests" do
        User.create(name: "lala")
        User.some_method_with_a_query_missing_index

        expect(@aggregator.results.certains.count).to eq(1)
      end
    end

    context "when ignore_queries_originated_in_test_code=false" do
      it "does not ignore queries originated in test code" do
        User.create(name: "lala")
        User.find_by(name: "any")

        expect(@aggregator.results.certains.count).to eq(1)
      end
    end

    it 'does not affect "affected rows" of a query' do
      User.create(name: "lala", city_id: 1)
      User.create(name: "popo", city_id: 1)
      User.create(name: "other", city_id: 2)

      affetected_rows = User.where(city_id: 1).update_all(age: 30)

      expect(affetected_rows).to eq(2)
    end
  end

  describe ".export_html_results" do
    it "adds a line with the correct origin in the HTML report" do
      described_class.watch_queries do
        User.find_by(name: "lala")
      end

      file = Tempfile.new
      described_class.export_html_results(file, stdout: spy)
      file.open
      file.rewind
      html = file.read

      expect(html).to match(%r{<td>certain</td>\n.+<td>User Load</td>})
      expect(html).to match(%r{<td>.+WHERE `users`.`name` = 'lala'.+</td>})
      expect(html).to match(%r{<td>spec/wt_activerecord_index_spy_spec.rb:\d+</td>})
    end
  end
end
